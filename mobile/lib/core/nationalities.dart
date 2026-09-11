const travellerNationalities = <String>[
  'Malaysian',
  'Australian',
  'Bangladeshi',
  'British',
  'Bruneian',
  'Cambodian',
  'Canadian',
  'Chinese',
  'Filipino',
  'French',
  'German',
  'Indian',
  'Indonesian',
  'Japanese',
  'Myanmar',
  'Nepalese',
  'New Zealander',
  'Pakistani',
  'Singaporean',
  'South Korean',
  'Sri Lankan',
  'Thai',
  'Vietnamese',
  'Other',
];

List<String> nationalityOptions([String currentNationality = '']) {
  if (currentNationality.isEmpty ||
      travellerNationalities.contains(currentNationality)) {
    return travellerNationalities;
  }
  // Preserve a legacy value so an existing profile can still display it,
  // without allowing new arbitrary text entry.
  return [currentNationality, ...travellerNationalities];
}
