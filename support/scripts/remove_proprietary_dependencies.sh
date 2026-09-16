#!/bin/sh

# This script removes proprietary dependencies from the project.

cd app

REGEX_A="s/\/\/ \[FOSS_REMOVE_START\]/\/*/"
REGEX_B="s/\/\/ \[FOSS_REMOVE_END\]/\*\//"

# Remove lines from pubspec.yaml
sed -i '/# \[FOSS_REMOVE\]/d' pubspec.yaml

# Comment out parts in Dart files
sed -i "$REGEX_A" lib/config/init.dart
sed -i "$REGEX_B" lib/config/init.dart

sed -i "$REGEX_A" lib/main.dart
sed -i "$REGEX_B" lib/main.dart

sed -i "$REGEX_A" lib/pages/donation/donation_page.dart
sed -i "$REGEX_B" lib/pages/donation/donation_page.dart

sed -i "$REGEX_A" lib/pages/donation/donation_page_vm.dart
sed -i "$REGEX_B" lib/pages/donation/donation_page_vm.dart

sed -i "$REGEX_A" lib/pages/about/about_page.dart
sed -i "$REGEX_B" lib/pages/about/about_page.dart

# Remove files completely
rm lib/provider/purchase_provider.dart

# Play Core (Google Play In-App Updates) cannot ship in FOSS/F-Droid builds either.
rm lib/provider/update_provider.dart
rm lib/widget/dialogs/update_dialog.dart

# Refer to donationPageNoopVmProvider instead of donationPageVmProvider
sed -i 's/donationPageVmProvider/donationPageNoopVmProvider/g' lib/pages/donation/donation_page.dart

cd ..
echo "Proprietary dependencies removed."
