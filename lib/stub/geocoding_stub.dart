// Web stub: geocoding is not supported on web

class Placemark {
  final String? street;
  final String? locality;
  final String? subLocality;
  final String? administrativeArea;
  final String? subAdministrativeArea;
  final String? thoroughfare;
  final String? subThoroughfare;
  final String? country;
  final String? isoCountryCode;
  final String? postalCode;
  const Placemark({
    this.street,
    this.locality,
    this.subLocality,
    this.administrativeArea,
    this.subAdministrativeArea,
    this.thoroughfare,
    this.subThoroughfare,
    this.country,
    this.isoCountryCode,
    this.postalCode,
  });
}

Future<List<Placemark>> placemarkFromCoordinates(
  double latitude,
  double longitude, {
  String? localeIdentifier,
}) async {
  return [];
}
