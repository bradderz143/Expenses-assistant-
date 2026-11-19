import '../reference/countries.dart';
import 'enums.dart';

const Object _unset = Object();

class AppSettings {
  const AppSettings({
    this.defaultCountry = Countries.defaultCountry,
    this.defaultClaimType = ClaimType.expense,
    this.activeTripId,
    this.favouriteCountries = const [Countries.defaultCountry],
    this.wifiOnlyModelDownloads = false,
  });

  /// Used when no active trip is set.
  final String defaultCountry;
  final ClaimType defaultClaimType;

  /// New captures are filed under this trip (and take its country).
  final String? activeTripId;
  final List<String> favouriteCountries;

  /// Translation models are ~30 MB per language.
  final bool wifiOnlyModelDownloads;

  AppSettings copyWith({
    String? defaultCountry,
    ClaimType? defaultClaimType,
    Object? activeTripId = _unset,
    List<String>? favouriteCountries,
    bool? wifiOnlyModelDownloads,
  }) {
    return AppSettings(
      defaultCountry: defaultCountry ?? this.defaultCountry,
      defaultClaimType: defaultClaimType ?? this.defaultClaimType,
      activeTripId: identical(activeTripId, _unset)
          ? this.activeTripId
          : activeTripId as String?,
      favouriteCountries: favouriteCountries ?? this.favouriteCountries,
      wifiOnlyModelDownloads:
          wifiOnlyModelDownloads ?? this.wifiOnlyModelDownloads,
    );
  }
}
