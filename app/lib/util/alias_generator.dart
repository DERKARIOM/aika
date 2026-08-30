import 'dart:math';

/// Simple, well-known manga/anime character names used as the default random
/// device name (replaces the previous "adjective + fruit" combination, e.g.
/// "Energetic Cherry"). Kept as plain, untranslated proper nouns since these
/// names are the same in every language.
const _mangaCharacterNames = [
  'Naruto', 'Sasuke', 'Sakura', 'Kakashi', 'Itachi', 'Gaara', 'Hinata', 'Shikamaru', 'Boruto', 'Jiraiya',
  'Luffy', 'Zoro', 'Nami', 'Sanji', 'Chopper', 'Robin', 'Usopp', 'Franky', 'Brook', 'Ace',
  'Goku', 'Vegeta', 'Gohan', 'Piccolo', 'Trunks', 'Bulma', 'Krillin', 'Frieza', 'Beerus', 'Broly',
  'Eren', 'Mikasa', 'Armin', 'Levi', 'Historia', 'Reiner', 'Annie', 'Erwin', 'Hange',
  'Light', 'Ryuk', 'Misa', 'Near', 'Mello',
  'Tanjiro', 'Nezuko', 'Zenitsu', 'Inosuke', 'Giyu', 'Shinobu', 'Rengoku', 'Muzan',
  'Deku', 'Bakugo', 'Todoroki', 'Ochaco', 'Iida', 'Kirishima',
  'Ichigo', 'Rukia', 'Renji', 'Byakuya', 'Orihime', 'Uryu', 'Toshiro',
  'Edward', 'Alphonse', 'Winry', 'Roy', 'Riza',
  'Gon', 'Killua', 'Kurapika', 'Leorio', 'Hisoka',
  'Kirito', 'Asuna', 'Klein', 'Sinon',
  'Saitama', 'Genos', 'Fubuki',
  'Yuji', 'Megumi', 'Nobara', 'Gojo', 'Sukuna',
  'Kaneki', 'Touka',
  'Natsu', 'Lucy', 'Erza', 'Gray', 'Wendy', 'Happy',
  'Shinji', 'Rei', 'Asuka', 'Misato',
  'Ash', 'Pikachu', 'Misty', 'Brock',
  'Usagi', 'Mamoru', 'Yugi', 'Kaiba', 'Joey',
];

String generateRandomAlias() {
  final random = Random();
  return _mangaCharacterNames[random.nextInt(_mangaCharacterNames.length)];
}
