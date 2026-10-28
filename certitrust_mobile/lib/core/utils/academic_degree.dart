class AcademicDegree {
  static const programSuggestions = [
    'Doctor of Information Technology (DIT)',
    'Doctor of Philosophy (PhD)',
    'MS Information Technology (MSIT)',
    'Master in Business Administration (MBA)',
    'BS Information Technology (BSIT)',
    'BS Computer Science (BSCS)',
    'BS Business Administration (BSBA)',
    'BS Education (BSEd)',
    'Cert. in Cybersecurity & Web Security',
    'Professional Certificate in Cybersecurity',
  ];

  static const levelOptions = [
    ('bachelors_first', "Bachelor's (1st Degree)"),
    ('second_degree', 'Second Degree'),
    ('masters', "Master's"),
    ('doctoral', 'Doctoral'),
    ('professional', 'Professional'),
  ];

  static String classify(String program, {int degreeNumber = 1}) {
    final normalized = program.trim().toLowerCase();
    final acronym = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');

    if (normalized.contains('master') ||
        RegExp(r'^(mba|ms|ma|mpa|mph|mfa)').hasMatch(acronym)) {
      return 'masters';
    }
    if (normalized.contains('doctor') ||
        const ['phd', 'dit', 'edd', 'dba', 'dpa', 'deng', 'md', 'jd']
            .any(acronym.startsWith)) {
      return 'doctoral';
    }
    if (normalized.contains('professional') ||
        normalized.contains('certification') ||
        normalized.startsWith('cert')) {
      return 'professional';
    }
    if (normalized.contains('bachelor') ||
        RegExp(r'^(bs|ba|beed|bsed|bshm|bstm|bsn|bsa)').hasMatch(acronym)) {
      return degreeNumber > 1 ? 'second_degree' : 'bachelors_first';
    }
    return degreeNumber > 1 ? 'second_degree' : 'other';
  }
}
