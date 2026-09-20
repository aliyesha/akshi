enum MonitorProfile {
  website,
  email,
  domainOnly;

  String get storageValue => switch (this) {
    MonitorProfile.website => 'website',
    MonitorProfile.email => 'email',
    MonitorProfile.domainOnly => 'domain',
  };

  String get label => switch (this) {
    MonitorProfile.website => 'Website',
    MonitorProfile.email => 'Email domain',
    MonitorProfile.domainOnly => 'Domain only',
  };

  String get description => switch (this) {
    MonitorProfile.website => 'Registration, certificate, and site identity',
    MonitorProfile.email => 'Registration and published mail configuration',
    MonitorProfile.domainOnly => 'Registration dates without a service check',
  };

  bool get checksCertificate => this == MonitorProfile.website;
  bool get checksEmail => this == MonitorProfile.email;
  bool get discoversSiteIcon => this == MonitorProfile.website;

  static MonitorProfile fromStorage(String? value) => switch (value) {
    'email' => MonitorProfile.email,
    'domain' => MonitorProfile.domainOnly,
    _ => MonitorProfile.website,
  };
}

enum EmailDirection {
  sendAndReceive,
  sendOnly,
  receiveOnly;

  bool get sends => this != EmailDirection.receiveOnly;
  bool get receives => this != EmailDirection.sendOnly;
}
