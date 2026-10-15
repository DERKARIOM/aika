//! Streaming ZIP archives for the web share page ("Télécharger en ZIP").
//!
//! The archive is written on the fly while the files are read: nothing is
//! stored on disk and only one chunk is held in memory at a time, so
//! selections of any size (including >100 GB) can be downloaded.
//!
//! Files are *stored* (no compression): photos and videos are already
//! compressed, and storing keeps the device's CPU and battery free. Because
//! the content is stored, the exact archive size is known before the first
//! byte is sent (`Content-Length`), so browsers show real progress.
//!
//! Each entry uses a data descriptor (the CRC-32 is only known once the
//! entry has been streamed). ZIP64 records are used only when needed
//! (archive of 4 GiB or more, or 65 535 entries or more), so smaller archives
//! stay readable by every unzip tool.

/// Most files accepted in one archive.
pub(crate) const MAX_ZIP_FILES: usize = 10_000;

const LOCAL_HEADER_SIG: u32 = 0x0403_4b50;
const DATA_DESCRIPTOR_SIG: u32 = 0x0807_4b50;
const CENTRAL_HEADER_SIG: u32 = 0x0201_4b50;
const ZIP64_EOCD_SIG: u32 = 0x0606_4b50;
const ZIP64_LOCATOR_SIG: u32 = 0x0706_4b50;
const EOCD_SIG: u32 = 0x0605_4b50;

/// Bit 3: sizes and CRC in a data descriptor; bit 11: UTF-8 names.
const FLAGS: u16 = 0x0808;
const VERSION_DEFAULT: u16 = 20;
const VERSION_ZIP64: u16 = 45;
const ZIP64_EXTRA_ID: u16 = 0x0001;

/// A file of the archive: its path inside the archive and its exact size.
#[derive(Debug, Clone)]
pub(crate) struct ZipEntry {
    pub(crate) name: String,
    pub(crate) size: u64,
}

/// Layout of a stored ZIP archive, computed before streaming.
pub(crate) struct ZipPlan {
    entries: Vec<ZipEntry>,
    /// Offset of each local header.
    offsets: Vec<u64>,
    zip64: bool,
    central_offset: u64,
    central_size: u64,
    total_len: u64,
    dos_time: u16,
    dos_date: u16,
}

impl ZipPlan {
    /// Plans an archive of `entries`, all dated `unix_secs` (UTC).
    pub(crate) fn new(entries: Vec<ZipEntry>, unix_secs: u64) -> Self {
        let classic = Self::layout(&entries, false);
        let zip64 = entries.len() >= 0xFFFF || classic.3 >= 0xFFFF_FFFF;
        let (offsets, central_offset, central_size, total_len) = if zip64 {
            Self::layout(&entries, true)
        } else {
            classic
        };
        let (dos_time, dos_date) = dos_date_time(unix_secs);
        Self {
            entries,
            offsets,
            zip64,
            central_offset,
            central_size,
            total_len,
            dos_time,
            dos_date,
        }
    }

    /// Same as [`ZipPlan::new`] with ZIP64 records even for a small archive.
    #[cfg(test)]
    fn new_zip64(entries: Vec<ZipEntry>, unix_secs: u64) -> Self {
        let (offsets, central_offset, central_size, total_len) = Self::layout(&entries, true);
        let (dos_time, dos_date) = dos_date_time(unix_secs);
        Self {
            entries,
            offsets,
            zip64: true,
            central_offset,
            central_size,
            total_len,
            dos_time,
            dos_date,
        }
    }

    /// (local header offsets, central directory offset, its size, total length).
    fn layout(entries: &[ZipEntry], zip64: bool) -> (Vec<u64>, u64, u64, u64) {
        let mut offsets = Vec::with_capacity(entries.len());
        let mut offset = 0u64;
        for entry in entries {
            offsets.push(offset);
            offset += local_header_len(entry, zip64) + entry.size + descriptor_len(zip64);
        }
        let central_offset = offset;
        let central_size: u64 = entries.iter().map(|e| central_header_len(e, zip64)).sum();
        let end_len = if zip64 { 56 + 20 + 22 } else { 22 };
        (
            offsets,
            central_offset,
            central_size,
            central_offset + central_size + end_len,
        )
    }

    /// Exact size of the archive in bytes.
    pub(crate) fn total_len(&self) -> u64 {
        self.total_len
    }

    pub(crate) fn len(&self) -> usize {
        self.entries.len()
    }

    pub(crate) fn entry(&self, index: usize) -> &ZipEntry {
        &self.entries[index]
    }

    fn version(&self) -> u16 {
        if self.zip64 {
            VERSION_ZIP64
        } else {
            VERSION_DEFAULT
        }
    }

    /// Local header of entry `index` (CRC and sizes follow in the descriptor).
    pub(crate) fn local_header(&self, index: usize) -> Vec<u8> {
        let name = self.entries[index].name.as_bytes();
        let mut out =
            Vec::with_capacity(local_header_len(&self.entries[index], self.zip64) as usize);
        put_u32(&mut out, LOCAL_HEADER_SIG);
        put_u16(&mut out, self.version());
        put_u16(&mut out, FLAGS);
        put_u16(&mut out, 0); // stored
        put_u16(&mut out, self.dos_time);
        put_u16(&mut out, self.dos_date);
        put_u32(&mut out, 0); // CRC-32: in the data descriptor
        put_u32(&mut out, 0); // compressed size: in the data descriptor
        put_u32(&mut out, 0); // uncompressed size: in the data descriptor
        put_u16(&mut out, name.len() as u16);
        put_u16(&mut out, if self.zip64 { 20 } else { 0 });
        out.extend_from_slice(name);
        if self.zip64 {
            // Announces 8-byte sizes in the data descriptor.
            put_u16(&mut out, ZIP64_EXTRA_ID);
            put_u16(&mut out, 16);
            put_u64(&mut out, 0);
            put_u64(&mut out, 0);
        }
        out
    }

    /// Data descriptor written after the content of entry `index`.
    pub(crate) fn data_descriptor(&self, index: usize, crc: u32) -> Vec<u8> {
        let size = self.entries[index].size;
        let mut out = Vec::with_capacity(descriptor_len(self.zip64) as usize);
        put_u32(&mut out, DATA_DESCRIPTOR_SIG);
        put_u32(&mut out, crc);
        if self.zip64 {
            put_u64(&mut out, size);
            put_u64(&mut out, size);
        } else {
            put_u32(&mut out, size as u32);
            put_u32(&mut out, size as u32);
        }
        out
    }

    /// Central directory and end records, once every CRC is known.
    pub(crate) fn central_directory(&self, crcs: &[u32]) -> Vec<u8> {
        let mut out = Vec::with_capacity((self.total_len - self.central_offset) as usize);
        for (index, entry) in self.entries.iter().enumerate() {
            let name = entry.name.as_bytes();
            put_u32(&mut out, CENTRAL_HEADER_SIG);
            put_u16(&mut out, self.version()); // made by (MS-DOS attributes)
            put_u16(&mut out, self.version()); // needed to extract
            put_u16(&mut out, FLAGS);
            put_u16(&mut out, 0); // stored
            put_u16(&mut out, self.dos_time);
            put_u16(&mut out, self.dos_date);
            put_u32(&mut out, crcs[index]);
            if self.zip64 {
                put_u32(&mut out, u32::MAX);
                put_u32(&mut out, u32::MAX);
            } else {
                put_u32(&mut out, entry.size as u32);
                put_u32(&mut out, entry.size as u32);
            }
            put_u16(&mut out, name.len() as u16);
            put_u16(&mut out, if self.zip64 { 28 } else { 0 });
            put_u16(&mut out, 0); // comment
            put_u16(&mut out, 0); // disk
            put_u16(&mut out, 0); // internal attributes
            put_u32(&mut out, 0); // external attributes
            put_u32(
                &mut out,
                if self.zip64 {
                    u32::MAX
                } else {
                    self.offsets[index] as u32
                },
            );
            out.extend_from_slice(name);
            if self.zip64 {
                put_u16(&mut out, ZIP64_EXTRA_ID);
                put_u16(&mut out, 24);
                put_u64(&mut out, entry.size);
                put_u64(&mut out, entry.size);
                put_u64(&mut out, self.offsets[index]);
            }
        }

        let count = self.entries.len() as u64;
        if self.zip64 {
            let zip64_eocd_offset = self.central_offset + self.central_size;
            put_u32(&mut out, ZIP64_EOCD_SIG);
            put_u64(&mut out, 44); // size of the rest of this record
            put_u16(&mut out, VERSION_ZIP64);
            put_u16(&mut out, VERSION_ZIP64);
            put_u32(&mut out, 0);
            put_u32(&mut out, 0);
            put_u64(&mut out, count);
            put_u64(&mut out, count);
            put_u64(&mut out, self.central_size);
            put_u64(&mut out, self.central_offset);

            put_u32(&mut out, ZIP64_LOCATOR_SIG);
            put_u32(&mut out, 0);
            put_u64(&mut out, zip64_eocd_offset);
            put_u32(&mut out, 1);
        }

        put_u32(&mut out, EOCD_SIG);
        put_u16(&mut out, 0);
        put_u16(&mut out, 0);
        let short_count = if self.zip64 { 0xFFFF } else { count as u16 };
        put_u16(&mut out, short_count);
        put_u16(&mut out, short_count);
        put_u32(
            &mut out,
            if self.zip64 {
                u32::MAX
            } else {
                self.central_size as u32
            },
        );
        put_u32(
            &mut out,
            if self.zip64 {
                u32::MAX
            } else {
                self.central_offset as u32
            },
        );
        put_u16(&mut out, 0); // comment
        out
    }
}

fn local_header_len(entry: &ZipEntry, zip64: bool) -> u64 {
    30 + entry.name.len() as u64 + if zip64 { 20 } else { 0 }
}

fn descriptor_len(zip64: bool) -> u64 {
    if zip64 {
        24
    } else {
        16
    }
}

fn central_header_len(entry: &ZipEntry, zip64: bool) -> u64 {
    46 + entry.name.len() as u64 + if zip64 { 28 } else { 0 }
}

fn put_u16(out: &mut Vec<u8>, value: u16) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn put_u32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn put_u64(out: &mut Vec<u8>, value: u64) {
    out.extend_from_slice(&value.to_le_bytes());
}

/// MS-DOS time and date of `unix_secs` (UTC), clamped to 1980–2107.
fn dos_date_time(unix_secs: u64) -> (u16, u16) {
    let days = (unix_secs / 86_400) as i64;
    let secs_of_day = unix_secs % 86_400;
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + if month <= 2 { 1 } else { 0 };

    if year < 1980 {
        return (0, (1 << 5) | 1); // 1980-01-01 00:00
    }
    let year = year.min(2107);
    let time = ((secs_of_day / 3600) << 11)
        | (((secs_of_day % 3600) / 60) << 5)
        | ((secs_of_day % 60) / 2);
    let date = (((year - 1980) as u64) << 9) | ((month as u64) << 5) | day as u64;
    (time as u16, date as u16)
}

/// CRC-32 (IEEE), as required by the ZIP format.
pub(crate) struct Crc32 {
    value: u32,
}

const CRC_TABLE: [u32; 256] = {
    let mut table = [0u32; 256];
    let mut i = 0;
    while i < 256 {
        let mut c = i as u32;
        let mut k = 0;
        while k < 8 {
            c = if c & 1 != 0 {
                0xEDB8_8320 ^ (c >> 1)
            } else {
                c >> 1
            };
            k += 1;
        }
        table[i] = c;
        i += 1;
    }
    table
};

impl Crc32 {
    pub(crate) fn new() -> Self {
        Self { value: 0xFFFF_FFFF }
    }

    pub(crate) fn update(&mut self, bytes: &[u8]) {
        let mut c = self.value;
        for &b in bytes {
            c = CRC_TABLE[((c ^ b as u32) & 0xFF) as usize] ^ (c >> 8);
        }
        self.value = c;
    }

    pub(crate) fn finish(&self) -> u32 {
        self.value ^ 0xFFFF_FFFF
    }
}

/// Safe, unique paths inside the archive for the given file names: no
/// absolute paths, no `..`, no control characters, and duplicates become
/// `name (2).ext`. Folders in shared names (`dir/file`) are kept.
pub(crate) fn zip_entry_names<'a>(names: impl Iterator<Item = &'a str>) -> Vec<String> {
    let mut used = std::collections::HashSet::new();
    names
        .map(|name| {
            let clean = clean_entry_name(name);
            let mut candidate = clean.clone();
            let mut n = 2;
            while !used.insert(candidate.to_lowercase()) {
                candidate = with_suffix(&clean, n);
                n += 1;
            }
            candidate
        })
        .collect()
}

fn clean_entry_name(name: &str) -> String {
    let parts: Vec<String> = name
        .replace('\\', "/")
        .split('/')
        .map(|part| part.chars().filter(|c| !c.is_control()).collect::<String>())
        .map(|part| part.trim().to_string())
        .filter(|part| !part.is_empty() && part != "." && part != "..")
        .collect();
    let mut joined = parts.join("/");
    // Names are stored with a 16-bit length; keep them well below.
    while joined.len() > 1000 {
        joined.pop();
    }
    if joined.is_empty() {
        "file".to_string()
    } else {
        joined
    }
}

fn with_suffix(name: &str, n: usize) -> String {
    let (dir, file) = match name.rfind('/') {
        Some(i) => (&name[..=i], &name[i + 1..]),
        None => ("", name),
    };
    match file.rfind('.') {
        Some(dot) if dot > 0 => format!("{dir}{} ({n}){}", &file[..dot], &file[dot..]),
        _ => format!("{dir}{file} ({n})"),
    }
}

/// File name of the archive itself: the given name without path or control
/// characters, `.zip` added, `Aika.zip` by default.
pub(crate) fn zip_file_name(name: Option<&str>) -> String {
    let clean: String = name
        .unwrap_or("")
        .chars()
        .filter(|c| {
            !c.is_control() && !matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|')
        })
        .collect::<String>()
        .trim()
        .trim_matches('.')
        .chars()
        .take(100)
        .collect();
    let base = if clean.is_empty() {
        "Aika".to_string()
    } else {
        clean
    };
    if base.to_lowercase().ends_with(".zip") {
        base
    } else {
        format!("{base}.zip")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crc32_matches_reference() {
        let mut crc = Crc32::new();
        crc.update(b"123456789");
        assert_eq!(crc.finish(), 0xCBF4_3926);
        let mut split = Crc32::new();
        split.update(b"1234");
        split.update(b"56789");
        assert_eq!(split.finish(), 0xCBF4_3926);
        assert_eq!(Crc32::new().finish(), 0);
    }

    #[test]
    fn dos_dates() {
        // 2026-10-15 14:30:20 UTC
        let (time, date) = dos_date_time(1_792_074_620);
        assert_eq!(date >> 9, 2026 - 1980);
        assert_eq!((date >> 5) & 0xF, 10);
        assert_eq!(date & 0x1F, 15);
        assert_eq!(time >> 11, 14);
        assert_eq!((time >> 5) & 0x3F, 30);
        assert_eq!((time & 0x1F) * 2, 20);
        assert_eq!(dos_date_time(0), (0, 33));
    }

    #[test]
    fn entry_names_are_safe_and_unique() {
        let names = zip_entry_names(
            [
                "a.jpg",
                "A.jpg",
                "../../etc/passwd",
                "/abs/x.txt",
                "dir\\b.txt",
                "",
                "a.jpg",
                "note",
                "note",
            ]
            .into_iter(),
        );
        assert_eq!(
            names,
            [
                "a.jpg",
                "A (2).jpg",
                "etc/passwd",
                "abs/x.txt",
                "dir/b.txt",
                "file",
                "a (3).jpg",
                "note",
                "note (2)"
            ]
        );
    }

    #[test]
    fn archive_file_name() {
        assert_eq!(zip_file_name(None), "Aika.zip");
        assert_eq!(zip_file_name(Some("Vacances d'été")), "Vacances d'été.zip");
        assert_eq!(zip_file_name(Some("../x/y.zip")), "xy.zip");
        assert_eq!(zip_file_name(Some("  ..  ")), "Aika.zip");
    }

    #[test]
    fn plan_length_matches_written_bytes() {
        for big in [false, true] {
            let entries: Vec<ZipEntry> = if big {
                // Forces ZIP64 (sizes are only announced, nothing is written).
                vec![ZipEntry {
                    name: "big.bin".into(),
                    size: 5 * 1024 * 1024 * 1024,
                }]
            } else {
                vec![
                    ZipEntry {
                        name: "a.txt".into(),
                        size: 3,
                    },
                    ZipEntry {
                        name: "dossier/é.txt".into(),
                        size: 0,
                    },
                ]
            };
            let plan = ZipPlan::new(entries, 1_792_074_620);
            assert_eq!(plan.zip64, big);
            let mut len = 0u64;
            for i in 0..plan.len() {
                len += plan.local_header(i).len() as u64
                    + plan.entry(i).size
                    + plan.data_descriptor(i, 0).len() as u64;
            }
            len += plan.central_directory(&vec![0; plan.len()]).len() as u64;
            assert_eq!(len, plan.total_len());
        }
    }

    /// Writes a complete small archive (content included) for external checks.
    fn write_archive(plan: &ZipPlan, contents: &[&[u8]]) -> Vec<u8> {
        let mut out = Vec::new();
        let mut crcs = Vec::new();
        for (i, content) in contents.iter().enumerate() {
            out.extend(plan.local_header(i));
            out.extend_from_slice(content);
            let mut crc = Crc32::new();
            crc.update(content);
            crcs.push(crc.finish());
            out.extend(plan.data_descriptor(i, crcs[i]));
        }
        out.extend(plan.central_directory(&crcs));
        out
    }

    #[test]
    fn zip64_archive_is_consistent() {
        let entries = vec![
            ZipEntry {
                name: "a.txt".into(),
                size: 5,
            },
            ZipEntry {
                name: "photos/été.jpg".into(),
                size: 3,
            },
        ];
        let plan = ZipPlan::new_zip64(entries, 1_792_074_620);
        let zip = write_archive(&plan, &[b"hello", b"abc"]);
        assert_eq!(zip.len() as u64, plan.total_len());
        if let Ok(path) = std::env::var("AIKA_ZIP64_TEST_OUT") {
            std::fs::write(path, &zip).unwrap();
        }
    }
}
