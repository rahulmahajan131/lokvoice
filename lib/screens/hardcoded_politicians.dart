class Politician {
  final String id;
  final String name;
  final String role;
  final String party;
  final String photoAsset;
  final String partyLogoAsset;

  Politician({
    required this.id,
    required this.name,
    required this.role,
    required this.party,
    this.photoAsset = '',
    this.partyLogoAsset = '',
  });
}

final List<Politician> hardcodedPoliticians = [
  Politician(
    id: 'rahul_gandhi',
    name: 'Rahul Gandhi',
    role: 'Member of Parliament',
    party: 'Congress',
    photoAsset: 'assets/rahul.png',
    partyLogoAsset: 'assets/congress_logo.png',
  ),
  Politician(
    id: 'narendra_modi',
    name: 'Narendra Modi',
    role: 'Prime Minister',
    party: 'BJP',
    photoAsset: 'assets/modi.png',
    partyLogoAsset: 'assets/bjp_logo.png',
  ),
  // Add more politicians here as needed
];
