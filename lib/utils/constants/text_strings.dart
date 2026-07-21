/// Supported UI languages.
enum AppLanguage { km, en }

/// Central store of all user-facing static text, in Khmer + English.
///
/// Read strings in widgets via the current [AppTexts] instance exposed by
/// `SettingsProvider`:
///
/// ```dart
/// final s = context.watch<SettingsProvider>();
/// Text(s.t.navMap); // 'ផែនទី' or 'Map'
/// ```
///
/// Add new UI text as getters here (Khmer first, English second) instead of
/// hardcoding it in widgets, so every string lives in one place.
class AppTexts {
  final AppLanguage lang;
  const AppTexts(this.lang);

  bool get _km => lang == AppLanguage.km;

  // ─── Bottom navigation ─────────────────────────────────────────────────
  String get navMap => _km ? 'ផែនទី' : 'Map';
  String get navBookmarks => _km ? 'ចំណាំ' : 'Bookmarks';
  String get navContribute => _km ? 'ចូលរួម' : 'Contribute';
  String get navAccount => _km ? 'គណនី' : 'Account';

  // ─── Account screen ────────────────────────────────────────────────────
  String get noAccount => _km ? 'មិនមានគណនី' : 'No Account';
  String get accountPrompt => _km
      ? 'សូមបង្កើតឬចូលក្នុងគណនីដើម្បីរក្សាទុកទិន្នន័យ និងទទួលបានបទពិសោធន៍ពេញលេញជាមួយ KH-Map'
      : 'Please create or login to an account to save data and get the full experience with KH-Map';
  String get login => _km ? 'ចូលគណនី' : 'Login';
  String get changeAccount => _km ? 'ផ្លាស់ប្តូរគណនី' : 'Change Account';
  String get settings => _km ? 'ការកំណត់' : 'Settings';
  String get darkMode => _km ? 'ប្ដូរពណ៌ផ្ទាំង' : 'Dark Mode';
  String get language => _km ? 'ភាសា' : 'Language';
  String get technicalSupport => _km ? 'ជំនួយបច្ចេកទេស' : 'Technical Support';
  String get noNameFound => _km ? 'គ្មានឈ្មោះ' : 'No Name Found';

  // ─── Common actions / words (reused across screens) ────────────────────
  String get cancel => _km ? 'បោះបង់' : 'Cancel';
  String get save => _km ? 'រក្សាទុក' : 'Save';
  String get create => _km ? 'បង្កើត' : 'Create';
  String get delete => _km ? 'លុប' : 'Delete';
  String get edit => _km ? 'កែសម្រួល' : 'Edit';
  String get close => _km ? 'បិទ' : 'Close';
  String get yes => _km ? 'យល់ព្រម' : 'Yes';
  String get tryAgain => _km ? 'ព្យាយាមម្តងទៀត' : 'Try again';

  // ─── Search ────────────────────────────────────────────────────────────
  String get searchPlacesHint => _km ? 'ស្វែងរកទីកន្លែង . . .' : 'Search places . . .';
  String get searchHereHint => _km ? 'ស្វែងរកនៅទីនេះ' : 'Search here';
  String get searchHistory => _km ? 'ប្រវត្តិស្វែងរក' : 'Search history';
  String get results => _km ? 'លទ្ធផល' : 'Results';
  String resultsCount(int n) => _km ? 'លទ្ធផល ($n)' : 'Results ($n)';
  String get showLess => _km ? 'បង្ហាញតិច' : 'Show less';
  String showMore(int n) => _km ? 'បង្ហាញបន្ថែម ($n)' : 'Show more ($n)';
  String noResultsFor(String q) =>
      _km ? 'រកមិនឃើញលទ្ធផលសម្រាប់ "$q"' : 'No results for "$q"';
  String get couldNotLoadPlaces =>
      _km ? 'មិនអាចទាញយកទីកន្លែងបានទេ' : 'Could not load places';
  String get searchEmptyPrompt => _km
      ? 'ចាប់ផ្តើមវាយដើម្បីស្វែងរកទីកន្លែង ឬចំណតឡានក្រុង'
      : 'Start typing to search for a place or bus stop';

  // Map search-bar category chips.
  String get catRestaurant => _km ? 'ភោជនីយដ្ឋាន' : 'Restaurant';
  String get catHotel => _km ? 'សណ្ឋាគារ' : 'Hotel';
  String get catMarket => _km ? 'ផ្សារ' : 'Market';
  String get catEntertainment => _km ? 'កន្លែងកម្សាន្ត' : 'Entertainment';
  String get catCoffee => _km ? 'ហាងកាហ្វេ' : 'Coffee';

  /// Localized label for a map search-bar category [key]. Falls back to the
  /// key itself for anything unmapped.
  String mapCategoryLabel(String key) {
    switch (key) {
      case 'restaurant':
        return catRestaurant;
      case 'hotel':
        return catHotel;
      case 'market':
        return catMarket;
      case 'entertainment':
        return catEntertainment;
      case 'coffee':
        return catCoffee;
      default:
        return key;
    }
  }

  // Search-screen quick categories.
  String get quickHome => _km ? 'លំនៅឋាន' : 'Home';
  String get quickWork => _km ? 'កន្លែងធ្វើការ' : 'Workplace';
  String get quickSchool => _km ? 'សាលារៀន' : 'School';
  String get quickOther => _km ? 'ផ្សេងៗ' : 'Others';

  // ─── Route planner / overlay ───────────────────────────────────────────
  String get routePlanner => _km ? 'គម្រោងធ្វើដំណើរ' : 'Route Planner';
  String get currentLocation => _km ? 'ទីតាំងបច្ចុប្បន្ន' : 'Current location';
  String get useCurrentLocation =>
      _km ? 'ប្រើទីតាំងបច្ចុប្បន្ន' : 'Use current location';
  String get pickFromMap => _km ? 'ជ្រើសពីផែនទី' : 'Pick from map';
  String changeLocationTitle(bool isOrigin) => isOrigin
      ? (_km ? 'ប្ដូរទីតាំងចេញដំណើរ?' : 'Change origin?')
      : (_km ? 'ប្ដូរគោលដៅ?' : 'Change destination?');
  String changeLocationBody(bool isOrigin) => isOrigin
      ? (_km
          ? 'តើអ្នកចង់ប្ដូរទីតាំងចេញដំណើររបស់អ្នកឬ?'
          : "Do you want to change your origin's location?")
      : (_km
          ? 'តើអ្នកចង់ប្ដូរគោលដៅរបស់អ្នកឬ?'
          : "Do you want to change your destination's location?");

  // ─── Bookmarks ─────────────────────────────────────────────────────────
  String get favoritePlaces => _km ? 'ទីកន្លែងពេញចិត្ត' : 'Favorite places';
  String get favoriteRoutes => _km ? 'ផ្លូវពេញចិត្ត' : 'Favorite routes';
  String get placesTab => _km ? 'ទីកន្លែង' : 'Places';
  String get routesTab => _km ? 'ផ្លូវ' : 'Routes';
  String get loading => _km ? 'កំពុងផ្ទុក...' : 'Loading...';
  String savedPlacesCount(int n) =>
      _km ? '$n ទីកន្លែងបានរក្សាទុក' : '$n saved places';
  String savedRoutesCount(int n) =>
      _km ? '$n ផ្លូវបានរក្សាទុក' : '$n saved routes';
  String get myFavoritesList =>
      _km ? 'បញ្ជីចំណូលចិត្តរបស់ខ្ញុំ' : 'My favorites list';
  String privateListCount(int n) =>
      _km ? 'បញ្ជីឯកជន · $n ទីកន្លែង' : 'Private list · $n places';
  String get all => _km ? 'ទាំងអស់' : 'All';
  String get showAll => _km ? 'បង្ហាញទាំងអស់' : 'Show all';

  // Sort menu.
  String get sort => _km ? 'តម្រៀប' : 'Sort';
  String get sortRecent => _km ? 'ថ្មីៗបំផុត' : 'Most recent';
  String get sortName => _km ? 'តាមឈ្មោះ (ក-អ)' : 'By name (A-Z)';
  String get sortRating => _km ? 'ការវាយតម្លៃខ្ពស់' : 'Highest rated';
  String get sortDistance => _km ? 'ចម្ងាយជិតបំផុត' : 'Nearest';
  String get deleteAll => _km ? 'លុបទាំងអស់' : 'Delete all';

  // Empty / error states.
  String get noSavedPlaces =>
      _km ? 'មិនទាន់មានទីកន្លែងដែលបានរក្សាទុក' : 'No saved places yet';
  String get noSavedPlacesHint => _km
      ? 'ប៉ះរូបតំណាងចំណាំនៅលើទីកន្លែងណាមួយក្នុងផែនទី ដើម្បីរក្សាទុកវានៅទីនេះ។'
      : 'Tap the bookmark icon on any place on the map to save it here.';
  String get noSavedRoutes =>
      _km ? 'មិនទាន់មានផ្លូវដែលបានរក្សាទុក' : 'No saved routes yet';
  String get noSavedRoutesHint => _km
      ? 'ប៉ះរូបតំណាងចំណាំនៅលើកាតផ្លូវ ពេលស្វែងរកទិសដៅ ដើម្បីរក្សាទុកវានៅទីនេះ។'
      : 'Tap the bookmark icon on a route card while planning a trip to save it here.';
  String get noPlacesInCategory =>
      _km ? 'គ្មានទីកន្លែងក្នុងប្រភេទនេះ' : 'No places in this category';
  String get couldNotLoadSavedPlaces => _km
      ? 'មិនអាចទាញយកទីកន្លែងដែលបានរក្សាទុកបានទេ'
      : 'Could not load saved places';
  String get couldNotLoadSavedRoutes =>
      _km ? 'មិនអាចទាញយកផ្លូវដែលបានរក្សាទុកបានទេ' : 'Could not load saved routes';

  // Clear-all dialog + snackbars.
  String get clearAllBookmarksTitle =>
      _km ? 'លុបចំណាំទាំងអស់?' : 'Remove all bookmarks?';
  String clearAllBookmarksBody(int n) => _km
      ? 'ទីកន្លែងដែលបានរក្សាទុកទាំង $n នឹងត្រូវបានយកចេញ។'
      : 'All $n saved places will be removed.';
  String get allBookmarksCleared =>
      _km ? 'បានលុបចំណាំទាំងអស់' : 'All bookmarks cleared';
  String get undo => _km ? 'មិនធ្វើវិញ' : 'Undo';
  String removedFromBookmarks(String name) =>
      _km ? 'បានលុប «$name» ចេញពីចំណាំ' : 'Removed "$name" from bookmarks';
  String get routeRemovedFromBookmarks =>
      _km ? 'បានលុបផ្លូវចេញពីចំណាំ' : 'Route removed from bookmarks';

  // Cards / sheets.
  String get options => _km ? 'ជម្រើស' : 'Options';
  String get remove => _km ? 'លុបចេញ' : 'Remove';
  String get copyLocation => _km ? 'ចម្លងទីតាំង' : 'Copy location';
  String get removeFromBookmarks => _km ? 'លុបចេញពីចំណាំ' : 'Remove from bookmarks';
  String copiedLocation(String text) =>
      _km ? 'បានចម្លងទីតាំង៖ $text' : 'Location copied: $text';
  String get category => _km ? 'ប្រភេទ' : 'Category';
  String get rating => _km ? 'ការវាយតម្លៃ' : 'Rating';
  String ratingsCount(int n) => _km ? '$n ការវាយតម្លៃ' : '$n ratings';
  String get noRatingsYet => _km ? 'មិនទាន់មានការវាយតម្លៃ' : 'No ratings yet';
  String get coordinates => _km ? 'កូអរដោនេ' : 'Coordinates';
  String coordinatesFromYou(String dist) =>
      _km ? 'កូអរដោនេ  ·  $dist ពីអ្នក' : 'Coordinates  ·  $dist from you';
  String get bookmarkStatus => _km ? 'ស្ថានភាពចំណាំ' : 'Bookmark status';
  String get showDirections => _km ? 'ចង្អុលផ្លូវ' : 'Directions';
  String get startLabel => _km ? 'ដើម' : 'Start';
  String get destinationLabel => _km ? 'គោលដៅ' : 'Destination';
  String get couldNotLoadRoute => _km ? 'មិនអាចទាញយកផ្លូវបានទេ' : 'Could not load route';
  String get noRouteForLocation =>
      _km ? 'រកមិនឃើញផ្លូវសម្រាប់ទីតាំងនេះទេ' : 'No route found for this location';

  // Distance units.
  String distanceMeters(int m) => _km ? '$m ម' : '$m m';
  String distanceKm(String km) => _km ? '$km គម' : '$km km';

  // ─── Admin ─────────────────────────────────────────────────────────────
  String failedWith(String msg) => _km ? 'បរាជ័យ: $msg' : 'Failed: $msg';
  String get confirmWord => _km ? 'បញ្ជាក់' : 'Confirm';
  String get no => _km ? 'ទេ' : 'No';
  String get pickColor => _km ? 'ជ្រើសរើសពណ៌' : 'Pick color';

  // Admin shell tabs (places/routes reuse placesTab/routesTab; account reuses navAccount).
  String get adminDashboardTab => _km ? 'ផ្ទាំង' : 'Dashboard';

  // Dashboard.
  String get adminDashboardTitle => _km ? 'ផ្ទាំងគ្រប់គ្រង' : 'Dashboard';
  String get currentStatus => _km ? 'ស្ថានភាពបច្ចុប្បន្ន' : 'Current status';
  String get overPeriod => _km ? 'ក្នុងថេរវេលា' : 'Over period';
  String get simulated => _km ? 'ក្លែងធ្វើ' : 'Simulation';
  String get live => _km ? 'ផ្សាយផ្ទាល់' : 'Live';
  String get systemMode => _km ? 'របៀបប្រព័ន្ធ' : 'System mode';

  // Places management.
  String get managePlaces => _km ? 'គ្រប់គ្រងទីកន្លែង' : 'Manage places';
  String get newPlace => _km ? 'បង្កើតទីកន្លែង' : 'New place';
  String get searchByName => _km ? 'ស្វែងរកតាមឈ្មោះ' : 'Search by name';
  String get noPlaces => _km ? 'មិនមានទីកន្លែង' : 'No places';
  String get deletePlaceTitle => _km ? 'លុបទីកន្លែង?' : 'Delete place?';
  String deleteQuoted(String name) => _km ? 'លុប "$name"?' : 'Delete "$name"?';
  String get cannotDeleteInUse => _km ? 'មិនអាចលុបបានទេ' : 'Cannot delete (in use)';
  String usedInRoutes(String name, int n) => _km
      ? '"$name" ត្រូវបានប្រើនៅក្នុង $n ផ្លូវ៖'
      : '"$name" is used in $n routes:';
  String usedInNRoutes(int n) => _km ? 'ប្រើក្នុង $n ផ្លូវ' : 'Used in $n routes';
  String get usageNA => _km ? 'ប្រើក្នុង N/A ផ្លូវ' : 'Used in N/A routes';
  String get usageUnavailable =>
      _km ? 'ការប្រើប្រាស់មិនអាចប្រើបាន' : 'Usage unavailable';

  // Place detail rows.
  String get khmerName => _km ? 'ឈ្មោះខ្មែរ' : 'Khmer name';
  String get latinName => _km ? 'ឈ្មោះឡាតាំង' : 'Latin name';
  String get ratingCount => _km ? 'ចំនួនផ្តល់ពិន្ទុ' : 'Rating count';
  String get averageRating => _km ? 'ពិន្ទុមធ្យម' : 'Average rating';
  String get photosCountLabel => _km ? 'ចំនួនរូបភាព' : 'Photos';
  String get noPhotos => _km ? 'មិនមានរូបភាព' : 'No photos';

  // Place edit.
  String get khmerNameRequired =>
      _km ? 'សូមបញ្ចូលឈ្មោះជាភាសាខ្មែរ' : 'Khmer name required';
  String get latinNameRequired =>
      _km ? 'សូមបញ្ចូលឈ្មោះជាអក្សរឡាតាំង' : 'Latin name required';
  String get categoryRequired =>
      _km ? 'សូមជ្រើសរើសប្រភេទ' : 'Category required';
  String get tapMapToSetLocation =>
      _km ? 'ចុចលើផែនទីដើម្បីកំណត់ទីតាំង' : 'Tap the map to set location';
  String photoFailed(String e) => _km ? 'រូបភាពបរាជ័យ: $e' : 'Photo failed: $e';
  String get editPlaceTitle => _km ? 'កែទីកន្លែង' : 'Edit place';
  String get newPlaceTitle => _km ? 'បង្កើតទីកន្លែង' : 'New place';
  String get tapToPlace =>
      _km ? 'ចុចលើផែនទីដើម្បីដាក់ទីតាំង' : 'Tap the map to place';

  // Routes management.
  String get manageRoutes => _km ? 'គ្រប់គ្រងផ្លូវ' : 'Manage routes';
  String get newRoute => _km ? 'បង្កើតផ្លូវ' : 'New route';
  String get searchByNameCode =>
      _km ? 'ស្វែងរកតាមឈ្មោះ/លេខ' : 'Search by name/code';
  String get noRoutesYet => _km ? 'មិនទាន់មានផ្លូវ' : 'No routes yet';
  String get noName => _km ? 'គ្មានឈ្មោះ' : 'No name';
  String stopsCount(int n) => _km ? '$n ចំណត' : '$n stops';
  String get stopsCountUnknown => _km ? '… ចំណត' : '… stops';
  String get showOnMap => _km ? 'បង្ហាញលើផែនទី' : 'Show on map';
  String statusArrow(String next) => _km ? 'ស្ថានភាព → $next' : 'Status → $next';

  // Route type (mirrors AdminRoute.typeLabel).
  String adminRouteType(bool isLine, String? direction) {
    if (isLine) return _km ? 'រង្វិលជុំ' : 'Loop';
    if (direction == 'inbound') return _km ? 'ទិសដៅ · ចូល' : 'Line · inbound';
    if (direction == 'outbound') return _km ? 'ទិសដៅ · ចេញ' : 'Line · outbound';
    return _km ? 'ទិសដៅ' : 'Line';
  }

  // Route create / edit.
  String get routeNameRequired =>
      _km ? 'សូមបញ្ចូលឈ្មោះផ្លូវ' : 'Route name required';
  String get pickAtLeastOneStop =>
      _km ? 'សូមជ្រើសរើសចំណតយ៉ាងតិច១' : 'Pick at least one stop';
  String get stopsAppended => _km ? 'បានបន្ថែមចំណត' : 'Stops appended';
  String get routeCreated => _km ? 'បានបង្កើតផ្លូវ' : 'Route created';
  String get routeSaved => _km ? 'បានរក្សាទុក' : 'Saved';
  String get cancelQuestion => _km ? 'បោះបង់?' : 'Cancel?';
  String get workWillBeLost =>
      _km ? 'ការងារនឹងបាត់បង់។ បោះបង់?' : 'Your work will be lost. Cancel?';
  String appendStopsLabel(String label) =>
      _km ? 'បន្ថែមចំណត · $label' : 'Append stops · $label';
  String get newRouteTitle => _km ? 'បង្កើតផ្លូវថ្មី' : 'New route';
  String get editRouteTitle => _km ? 'កែផ្លូវ' : 'Edit route';
  String get stepRouteInfo => _km ? 'ដំណាក់កាល ១/៤ · ព័ត៌មានផ្លូវ' : 'Step 1/4 · Route info';
  String get routeNameField => _km ? 'ឈ្មោះផ្លូវ' : 'Route name';
  String get codeOptional => _km ? 'កូដ (ស្រេចចិត្ត)' : 'Code (optional)';
  String get loopCircular => _km ? 'រង្វង់ / Loop' : 'Loop (circular)';
  String get departureEqualsTerminal =>
      _km ? 'ចំណតចេញ = ចំណតចុង' : 'Departure = terminal';
  String get directionalLine => _km ? 'បន្ទាត់មានទិសដៅ' : 'Directional line';
  String get direction => _km ? 'ទិសដៅ' : 'Direction';
  String get outbound => _km ? 'ចេញ' : 'Outbound';
  String get inbound => _km ? 'ចូល' : 'Inbound';
  String get directionPairingNote => _km
      ? 'ទិសដៅផ្គូចេញ និងចូលផ្គូផ្គងនៅក្រោមលេខកូដដូចគ្នា'
      : 'Outbound and inbound directions are paired under the same code';
  String get routeColor => _km ? 'ពណ៌ផ្លូវ' : 'Route color';
  String get nextPickStops => _km ? 'បន្ត · ជ្រើសរើសចំណត' : 'Next: pick stops';
  String stepPickStops(int n) =>
      _km ? 'ដំណាក់កាល ២/៤ · ជ្រើសរើសលំដាប់ចំណត ($n)' : 'Step 2/4 · Pick stop order ($n)';
  String get filterPlaces => _km ? 'ស្វែងរកចំណត' : 'Filter places';
  String get nextConnect => _km ? 'បន្ត · ភ្ជាប់' : 'Next: connect';
  String get noStopsPicked => _km
      ? 'មិនទាន់ជ្រើសរើស — ចុចទីកន្លែងដើម្បីបន្ថែម'
      : 'No stops picked — tap a place to add';
  String get noStops => _km ? 'មិនមានចំណត' : 'No stops';
  String segmentStepBanner(int idx, int total, String prev, String curr) {
    final head = _km ? 'ដំណាក់កាល ៣/៤' : 'Step 3/4';
    return '$head · Segment $idx / $total\n$prev → $curr';
  }
  String get stepReviewSave =>
      _km ? 'ដំណាក់កាល ៤/៤ · ពិនិត្យ & រក្សាទុក' : 'Step 4/4 · Review & save';
  String saveStops(int n) => _km ? 'រក្សាទុកចំណត ($n)' : 'Save stops ($n)';
  String createRouteWithStops(int n) =>
      _km ? 'បង្កើតផ្លូវ ($n ចំណត)' : 'Create route ($n stops)';

  // Segment-fix map hints.
  String get fetchingSuggestion =>
      _km ? 'កំពុងគណនាផ្លូវ…' : 'Fetching suggestion…';
  String manualDrawHint(int points) => _km
      ? '✏️ គូរដោយដៃ — បន្ទាត់តាមចំណុចរបស់អ្នក · $points ចំណុច'
      : '✏️ Manual: line follows your taps exactly · $points points';
  String get noSuggestionDrawHint => _km
      ? 'ផ្លូវមិនទាន់មាន — ចុច Suggest ឬចុចផែនទីដើម្បីគូរ'
      : 'No suggestion; tap the map to draw';
  String get wrongRoadDrawHint => _km
      ? 'ផ្លូវខុស? ចុចលើផែនទីដើម្បីគូរដោយដៃ'
      : 'Wrong road? Tap the map to draw the line yourself';
  String get saveDrawnLine =>
      _km ? 'រក្សាទុកបន្ទាត់ដែលគូរ' : 'Save drawn line';
  String get saveSuggestedPath =>
      _km ? 'រក្សាទុកផ្លូវណែនាំ' : 'Save suggested path';

  // Route detail.
  String get changePlaceQuestion => _km ? 'ប្ដូរទីកន្លែង?' : 'Change place?';
  String changePlaceMsg(String from, String to) =>
      _km ? 'ប្ដូរ "$from" ទៅ "$to"?' : 'Change "$from" to "$to"?';
  String get searchStops => _km ? 'ស្វែងរកចំណត' : 'Search stops';
  String deleteNStopsTitle(int n) =>
      _km ? 'លុបចំណត $n?' : 'Delete $n stops?';
  String deleteNStopsMsg(int n) => _km
      ? 'លុប $n ចំណតចេញពីផ្លូវ? ផ្លូវនឹងត្រូវគណនាឡើងវិញ។'
      : 'Delete $n stops from the route? Segments recompute automatically.';
  String deletedNStops(int n) => _km ? 'បានលុប $n ចំណត' : 'Deleted $n stops';
  String deletedSomeFailed(int ok, int fail, String names) => _km
      ? 'បានលុប $ok, បរាជ័យ $fail: $names'
      : 'Deleted $ok, failed $fail: $names';
  String get deleteStopTitle => _km ? 'លុបចំណត?' : 'Delete stop?';
  String deleteStopMsg(String name) =>
      _km ? 'លុប "$name" ចេញពីផ្លូវ?' : 'Delete "$name" from the route?';
  String get deleteWholeRouteTitle =>
      _km ? 'លុបផ្លូវទាំងមូល?' : 'Delete entire route?';
  String deleteRouteMsg(String name) => _km
      ? 'លុបផ្លូវ "$name" និងចំណតទាំងអស់? សកម្មភាពនេះមិនអាចត្រឡប់វិញបានទេ។'
      : 'Delete route "$name" and all its stops? This cannot be undone.';
  String nSelected(int n) => _km ? '$n បានជ្រើសរើស' : '$n selected';
  String get selectAll => _km ? 'ជ្រើសរើសទាំងអស់' : 'Select all';
  String get deleteSelectedStops =>
      _km ? 'លុបចំណតដែលបានជ្រើសរើស' : 'Delete selected stops';
  String get selectStops => _km ? 'ជ្រើសរើសច្រើន' : 'Select stops';
  String get editRoute => _km ? 'កែផ្លូវ' : 'Edit route';
  String get deleteRoute => _km ? 'លុបផ្លូវ' : 'Delete route';
  String get addStops => _km ? 'បន្ថែមចំណត' : 'Add stops';
  String get viewDetail => _km ? 'មើលព័ត៌មាន' : 'View detail';
  String get editSegment => _km ? 'កែផ្លូវចូល' : 'Edit segment';
  String get noStopsYet => _km ? 'មិនទាន់មានចំណត' : 'No stops yet';
  String get fixRoad => _km ? 'កែផ្លូវចូល' : 'Fix road';
  String get changePlace => _km ? 'ប្ដូរទីកន្លែង' : 'Change place';
  String fixRouteFor(String stop) => _km ? 'កែផ្លូវ · $stop' : 'Fix road · $stop';

  // Route edit.
  String get activeLabel => _km ? 'សកម្ម' : 'Active';
  String get activeOnDesc => _km ? 'បង្ហាញ & ដំណើរការ' : 'Shown & running';
  String get activeOffDesc => _km ? 'បិទ' : 'Hidden (inactive)';

  // ─── Place requests & reviews ──────────────────────────────────────────
  // Request status labels.
  String get statusApproved => _km ? 'បានអនុម័ត' : 'Approved';
  String get statusRejected => _km ? 'បានបដិសេធ' : 'Rejected';
  String get statusPending => _km ? 'កំពុងរង់ចាំ' : 'Pending';
  String placeStatusLabel(String status) {
    switch (status) {
      case 'approved':
        return statusApproved;
      case 'rejected':
        return statusRejected;
      default:
        return statusPending;
    }
  }

  String get approve => _km ? 'អនុម័ត' : 'Approve';
  String get reject => _km ? 'បដិសេធ' : 'Reject';
  String get refresh => _km ? 'ផ្ទុកឡើងវិញ' : 'Refresh';
  String get rejectionReasonLabel =>
      _km ? 'មូលហេតុនៃការបដិសេធ' : 'Rejection reason';
  String get notYet => _km ? 'មិនទាន់មាន' : 'Not yet';

  // Relative "N ago" phrase (no prefix); reused by request/review screens.
  String timeAgo(DateTime date) {
    final d = DateTime.now().difference(date);
    if (d.inDays >= 365) {
      final n = d.inDays ~/ 365;
      return _km ? '$n ឆ្នាំមុន' : (n == 1 ? '1 year ago' : '$n years ago');
    }
    if (d.inDays >= 30) {
      final n = d.inDays ~/ 30;
      return _km ? '$n ខែមុន' : (n == 1 ? '1 month ago' : '$n months ago');
    }
    if (d.inDays >= 7) {
      final n = d.inDays ~/ 7;
      return _km ? '$n សប្ដាហ៍មុន' : (n == 1 ? '1 week ago' : '$n weeks ago');
    }
    if (d.inDays >= 1) {
      return _km
          ? '${d.inDays} ថ្ងៃមុន'
          : (d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago');
    }
    if (d.inHours >= 1) {
      return _km
          ? '${d.inHours} ម៉ោងមុន'
          : (d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago');
    }
    if (d.inMinutes >= 1) {
      return _km
          ? '${d.inMinutes} នាទីមុន'
          : (d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago');
    }
    return _km ? 'អម្បាញ់មិញ' : 'Just now';
  }

  String submittedAgo(DateTime date) =>
      _km ? 'ស្នើ ${timeAgo(date)}' : 'Submitted ${timeAgo(date)}';
  String reviewedAgo(DateTime date) =>
      _km ? 'ត្រួតពិនិត្យ ${timeAgo(date)}' : 'Reviewed ${timeAgo(date)}';
  String reviewedAgoBy(DateTime date, String name) => _km
      ? 'ត្រួតពិនិត្យ ${timeAgo(date)} ដោយ $name'
      : 'Reviewed ${timeAgo(date)} by $name';
  String timeAgoBy(DateTime date, String name) =>
      _km ? '${timeAgo(date)} ដោយ $name' : '${timeAgo(date)} by $name';

  // Admin: place requests list.
  String get placeRequestsTitle => _km ? 'សំណើទីកន្លែង' : 'Place requests';
  String placeRequestsTitleCount(int n) =>
      _km ? 'សំណើទីកន្លែង ($n)' : 'Place requests ($n)';
  String get noNewRequests => _km ? 'គ្មានសំណើថ្មីទេ' : 'No new requests';
  String approvedShown(String name) => _km
      ? 'បានអនុម័ត «$name» — បង្ហាញលើផែនទីហើយ'
      : 'Approved "$name" — now shown on the map';
  String rejectedName(String name) =>
      _km ? 'បានបដិសេធ «$name»' : 'Rejected "$name"';

  // Admin: request detail.
  String get submittedBy => _km ? 'ស្នើដោយ' : 'Submitted by';
  String get submittedAt => _km ? 'ស្នើនៅ' : 'Submitted';
  String get reviewedLabel => _km ? 'ត្រួតពិនិត្យ' : 'Reviewed';
  String get locationOnMap => _km ? 'ទីតាំងលើផែនទី' : 'Location';
  String get reviewThisRequest =>
      _km ? 'សម្រេចលើសំណើនេះ' : 'Review this request';
  String get changeStatus => _km ? 'ផ្លាស់ប្ដូរស្ថានភាព' : 'Change status';

  // Admin: request history.
  String get reviewHistory => _km ? 'ប្រវត្តិការត្រួតពិនិត្យ' : 'Review history';
  String get noHistoryYet => _km ? 'គ្មានប្រវត្តិទេ' : 'No history yet';
  String filterAll(int n) => _km ? 'ទាំងអស់ ($n)' : 'All ($n)';
  String filterApproved(int n) => _km ? 'បានអនុម័ត ($n)' : 'Approved ($n)';
  String filterRejected(int n) => _km ? 'បានបដិសេធ ($n)' : 'Rejected ($n)';
  String submittedByName(String name) =>
      _km ? 'ស្នើដោយ $name' : 'Submitted by $name';
  String changedTo(String name, String status) => _km
      ? 'បានប្ដូរ «$name» ទៅ $status'
      : 'Changed "$name" to $status';

  // My requests sheet.
  String get newPlaceRequestStatus =>
      _km ? 'ស្ថានភាពនៃការស្នើសុំទីកន្លែងថ្មី' : 'Status of your new-place requests';
  String get noRequestsYet =>
      _km ? 'អ្នកមិនទាន់បានស្នើសុំទីកន្លែងថ្មីទេ' : "You haven't requested any new places yet";
  String get notShownOnMap => _km ? 'មិនបង្ហាញលើផែនទី' : 'Not shown on the map';

  // Reject-reason dialog.
  String get pleaseGiveRejectReason =>
      _km ? 'សូមបញ្ជាក់មូលហេតុនៃការបដិសេធ' : 'Please give a rejection reason';
  String rejectTitle(String name) =>
      _km ? 'បដិសេធ «$name»' : 'Reject "$name"';
  String get rejectReasonHelp => _km
      ? 'សូមសរសេររបាយការណ៍ថាហេតុអ្វីបានជាបដិសេធ ដើម្បីឲ្យអ្នកស្នើអាចមើលឃើញ និងកែសម្រួល។'
      : 'Explain why it was rejected so the submitter can see it and fix/re-submit.';
  String get rejectReasonHint => _km
      ? 'ឧ. រូបភាពមិនច្បាស់ / ទីតាំងមិនត្រឹមត្រូវ ...'
      : 'e.g. blurry photos / wrong location ...';

  // Reviews (place_reviews_screen + write_review_sheet).
  String get reviews => _km ? 'ការវាយតម្លៃ' : 'Reviews';
  String get writeReview => _km ? 'សរសេរការវាយតម្លៃ' : 'Write a review';
  String get submitReview => _km ? 'ផ្ញើការវាយតម្លៃ' : 'Submit review';
  String get reviewPosted => _km
      ? 'អរគុណ! ការវាយតម្លៃរបស់អ្នកត្រូវបានផ្សាយ។'
      : 'Thanks! Your review was posted.';
  String reviewsCount(int n) =>
      _km ? '$n ការវាយតម្លៃ' : (n == 1 ? '1 review' : '$n reviews');
  String get whatPeopleSaying => _km
      ? 'អ្វីដែលមនុស្សនិយាយអំពីទីកន្លែងនេះ'
      : 'What people are saying about this place';
  String get noReviewsYet => _km ? 'មិនទាន់មានការវាយតម្លៃ' : 'No reviews yet';
  String get beFirstToReview => _km
      ? 'ក្លាយជាអ្នកដំបូងដែលចែករំលែកបទពិសោធន៍របស់អ្នក។'
      : 'Be the first to share your experience.';
  String get couldNotLoadReviews =>
      _km ? 'មិនអាចទាញយកការវាយតម្លៃបានទេ' : 'Could not load reviews';
  String get commentLabel => _km ? 'មតិយោបល់' : 'Comment';
  String get reviewCommentHint => _km
      ? 'ចែករំលែកព័ត៌មានលម្អិតអំពីបទពិសោធន៍របស់អ្នកនៅទីកន្លែងនេះ…'
      : 'Share details of your experience at this place…';
  String get couldNotPickPhotos =>
      _km ? 'មិនអាចជ្រើសរូបភាពបានទេ' : 'Could not pick photos';
  String get pickStarRatingFirst =>
      _km ? 'សូមជ្រើសរើសផ្កាយជាមុនសិន' : 'Please pick a star rating first';
  String get logInToReview =>
      _km ? 'សូមចូលគណនីដើម្បីសរសេរការវាយតម្លៃ' : 'Please log in to write a review';
  String get couldNotSubmitReview => _km
      ? 'មិនអាចផ្ញើការវាយតម្លៃបានទេ — សូមព្យាយាមម្ដងទៀត'
      : 'Could not submit review — please try again';

  // ─── Auth (login / register / forgot password) ─────────────────────────
  String get passwordsDoNotMatch =>
      _km ? 'លេខសម្ងាត់មិនទាន់ត្រឹមត្រូវ' : 'Passwords do not match';
  String get loginSuccess => _km ? 'ចូលបានជោគជ័យ' : 'Signed in successfully';
  String get registerSuccess => _km
      ? 'បង្កើតគណនីជោគជ័យ! សូមចូលគណនី'
      : 'Account created! Please sign in';
  String get registerFailedEmailExists => _km
      ? 'ការចុះឈ្មោះបរាជ័យ (ប្រហែលជាមានអ៊ីមែលនេះរួចហើយ)'
      : 'Registration failed (this email may already exist)';
  String get registerFailed => _km ? 'ការចុះឈ្មោះបរាជ័យ' : 'Registration failed';
  String get cannotReachServer =>
      _km ? 'មិនអាចភ្ជាប់ទៅកាន់ Server បានទេ' : 'Could not reach the server';
  String get success => _km ? 'ជោគជ័យ!' : 'Success!';
  String get createAccount => _km ? 'បង្កើតគណនី' : 'Create account';
  String get loginSubtitle =>
      _km ? 'សូមបញ្ចូលអ៊ីមែល និងលេខសម្ងាត់' : 'Enter your email and password';
  String get registerSubtitle =>
      _km ? 'សូមបំពេញព័ត៌មានខាងក្រោម' : 'Fill in the details below';
  String get nameField => _km ? 'ឈ្មោះ' : 'Name';
  String get emailField => _km ? 'អ៊ីមែល' : 'Email';
  String get passwordField => _km ? 'លេខសម្ងាត់' : 'Password';
  String get confirmPasswordField =>
      _km ? 'ផ្ទៀងផ្ទាត់លេខសម្ងាត់' : 'Confirm password';
  String get forgotPasswordLink =>
      _km ? 'ភ្លេចលេខសម្ងាត់?' : 'Forgot password?';
  String get signIn => _km ? 'ចូល' : 'Sign in';
  String get signUp => _km ? 'ចុះឈ្មោះ' : 'Sign up';
  String get noAccountSignUp =>
      _km ? 'មិនទាន់មានគណនី? ចុះឈ្មោះនៅទីនេះ' : "Don't have an account? Sign up";
  String get haveAccountSignIn =>
      _km ? 'មានគណនីរួចហើយ? ចូលនៅទីនេះ' : 'Already have an account? Sign in';
  String get forgotPasswordTitle =>
      _km ? 'ភ្លេចលេខសម្ងាត់' : 'Forgot password';
  String get codeSent => _km ? 'លេខកូដត្រូវបានផ្ញើ!' : 'Code sent!';
  String get emailNotFound =>
      _km ? 'រកមិនឃើញអ៊ីមែលនេះទេ' : 'That email was not found';
  String get passwordChanged =>
      _km ? 'ប្តូរលេខសម្ងាត់ជោគជ័យ!' : 'Password changed successfully!';
  String get invalidCode => _km ? 'លេខកូដមិនត្រឹមត្រូវ' : 'Invalid code';
  String get enterCodeSubtitle => _km
      ? 'សូមបញ្ចូលលេខកូដ ៦ ខ្ទង់ដែលបានផ្ញើទៅកាន់អ៊ីមែលរបស់អ្នក'
      : 'Enter the 6-digit code sent to your email';
  String get enterEmailSubtitle => _km
      ? 'សូមបញ្ចូលអ៊ីមែលរបស់អ្នកដើម្បីទទួលបានលេខកូដ'
      : 'Enter your email to receive a code';
  String get codeField => _km ? 'លេខកូដ ៦ ខ្ទង់' : '6-digit code';
  String get newPasswordField => _km ? 'លេខសម្ងាត់ថ្មី' : 'New password';
  String get changePassword => _km ? 'ប្តូរលេខសម្ងាត់' : 'Change password';
  String get sendCode => _km ? 'ផ្ញើលេខកូដ' : 'Send code';

  // ─── Driver ────────────────────────────────────────────────────────────
  String get driverTitle => _km ? 'អ្នកបើកបរ' : 'Driver';
  String nextStopColon(String name) => _km ? 'បន្ទាប់: $name' : 'Next: $name';
  String get cancelTrip => _km ? 'បោះបង់ការធ្វើដំណើរ' : 'Cancel trip';
  String get tripsTitle => _km ? 'ដំណើរ' : 'Trips';
  String get today => _km ? 'ថ្ងៃនេះ' : 'Today';
  String get history => _km ? 'ប្រវត្តិ' : 'History';
  String get noTripsForYourBus =>
      _km ? 'មិនមានដំណើរសម្រាប់ឡានរបស់អ្នក' : 'No trips for your bus';
  String busNumberLabel(String n) => _km ? 'ឡានលេខ $n' : 'Bus $n';
  String get noStopData => _km ? 'មិនមានទិន្នន័យចំណត' : 'No stop data';
  String get tripDetails => _km ? 'ព័ត៌មានដំណើរ' : 'Trip details';
  String get startTrip => _km ? 'ចាប់ផ្តើមដំណើរ' : 'Start trip';
  String get turnOnShiftFirst =>
      _km ? 'សូមបើកវេនជាមុនសិន' : 'Turn on your shift first';
  String get locationPermissionRequired => _km
      ? 'ត្រូវការការអនុញ្ញាតទីតាំង'
      : 'Location permission required';
  String get home => _km ? 'ទំព័រដើម' : 'Home';
  String get tripFallbackName => _km ? 'ដំណើរ' : 'Trip';

  // ─── Map screen / bus panels ───────────────────────────────────────────
  String get couldNotSaveThisRoute =>
      _km ? 'មិនអាចរក្សាទុកផ្លូវនេះបានទេ' : 'Could not save this route';
  String get routeSavedToBookmarks =>
      _km ? 'បានរក្សាទុកផ្លូវទៅចំណាំ' : 'Route saved to bookmarks';
  String get couldNotSaveRoute =>
      _km ? 'មិនអាចរក្សាទុកផ្លូវបានទេ' : 'Could not save route';
  String get couldNotRemoveRoute =>
      _km ? 'មិនអាចលុបផ្លូវបានទេ' : 'Could not remove route';
  String categoryNotFoundNearby(String label) =>
      _km ? 'រកមិនឃើញ$labelទេ' : 'No $label found nearby';
  String get couldNotViewBusInfo => _km
      ? 'មិនអាចមើលព័ត៌មានរថយន្តបច្ចប្បន្នបានទេ'
      : 'Could not view this bus right now';
  String get busStopHeader =>
      _km ? 'ចំណតរថយន្តក្រុង · BUS STOP' : 'BUS STOP';
  String get routeItineraryHeader => _km
      ? 'ការធ្វើដំណើររបស់រថយន្តនេះ · ROUTE ITINERARY'
      : 'ROUTE ITINERARY';
  String get otherBusLinesHeader =>
      _km ? 'ខ្សែរត់ផ្សេងទៀតដែលឆ្លងកាត់ · OTHER BUS LINES' : 'OTHER BUS LINES';
  String get routeHeaderShort => _km ? 'ខ្សែរត់ · ROUTE' : 'ROUTE';
  String get plateNumber => _km ? 'ផ្លាកលេខ' : 'Plate number';
  String get statusLabel => _km ? 'ស្ថានភាព' : 'Status';
  String get nextStopHeader => _km ? 'ចំណតបន្ទាប់ · NEXT STOP' : 'NEXT STOP';
  String get selectRoutesHeader =>
      _km ? 'ជ្រើសរើសខ្សែរត់ · SELECT ROUTES' : 'SELECT ROUTES';
  String routeCodeLabel(String code) => _km ? 'ខ្សែរត់ $code' : 'Route $code';
  String get allStopsHeader => _km ? 'ចំណតទាំងអស់ · ALL STOPS' : 'ALL STOPS';
  String get directionsHeader => _km ? 'ទិសដៅរត់ · DIRECTIONS' : 'DIRECTIONS';
  String get startColon => _km ? 'ចាប់ផ្តើម: ' : 'Start: ';
  String get destinationColon => _km ? 'គោលដៅ: ' : 'Destination: ';
  String get navigationComingSoon => _km
      ? 'មុខងារនេះនឹងមកដល់ឆាប់ៗនេះ\n(Navigation coming soon)'
      : 'Navigation coming soon';
  String get notFoundShort => _km ? 'រកមិនឃើញ' : 'Not found';
  String foundPlaces(int n) => _km ? 'ឃើញ $n កន្លែង' : 'Found $n places';
  String get clearFilter => _km ? 'សម្អាត' : 'Clear';

  // ─── Route info card ───────────────────────────────────────────────────
  String get busShort => _km ? 'ឡានក្រុង' : 'Bus';
  String get walkShort => _km ? 'ដើរ' : 'Walk';
  String get removeRouteFromFavorites =>
      _km ? 'ដកចេញ​ថ្លូវធ្វើដំណើរពីចំណាំ' : 'Remove route from bookmarks';
  String get saveRouteToFavorites =>
      _km ? 'រក្សាទុក​ថ្លូវធ្វើដំណើរពីជាចំណាំ' : 'Save route to bookmarks';
  String get findingRoute => _km ? 'ស្វែងរកផ្លូវ…' : 'Finding route…';
  String get noRouteTryLater => _km
      ? 'គ្មានផ្លូវ — សូមព្យាយាមទម្តងទៀតនៅពេលក្រោយ'
      : 'No route — please try again later';

  // Friendly route-plan error messages (raw exceptions are never shown).
  String get routePlanTimeout => _km
      ? 'ការស្វែងរកផ្លូវយឺតជាងធម្មតា។ សូមព្យាយាមម្ដងទៀត។'
      : 'Finding a route is taking longer than usual. Please try again.';
  String get routePlanOffline => _km
      ? 'មិនអាចភ្ជាប់បណ្ដាញបានទេ។ សូមពិនិត្យអ៊ីនធឺណិតរបស់អ្នក រួចព្យាយាមម្ដងទៀត។'
      : "Can't connect. Please check your internet connection and try again.";
  String get routePlanGeneric => _km
      ? 'មិនអាចទាញយកផ្លូវបានទេ។ សូមព្យាយាមម្ដងទៀត។'
      : "Couldn't load the route. Please try again.";
  String minutesApprox(int n) => _km ? '~$n នាទី' : '~$n min';
  String walkDistance(String d) => _km ? 'ដើរ $d' : 'Walk $d';
  String get noTransfers => _km ? 'គ្មានការផ្ទេរ' : 'No transfers';
  String transfersCount(int n) => _km ? '$n ការផ្ទេរ' : '$n transfer(s)';
  String walkSegment(String label) => label.isEmpty
      ? walkShort
      : (_km ? 'ដើរ $label' : 'Walk $label');
  String get view => _km ? 'មើល' : 'View';
  String boardAtStop(String name) =>
      _km ? 'ឡើងនៅចំណត $name' : 'Board at $name';
  String alightAtStop(String name) =>
      _km ? 'ចុះនៅចំណត $name' : 'Alight at $name';
  String waitLive(int n) =>
      _km ? 'រយៈពេលរងចាំ ~$n នាទី 🟢' : 'Wait ~$n min 🟢';
  String waitEstimated(int n) =>
      _km ? 'ចាំ​ ~$n នាទី (ការប៉ាន់ស្មាន)' : 'Wait ~$n min (estimated)';
  String rideMinutes(int n) => _km ? 'ជិះ ~$n នាទី' : 'Ride ~$n min';
  String totalLegMinutes(int n) =>
      _km ? 'រយៈពេលសរុប ~$n នាទី' : 'Total ~$n min';

  // ─── Contributions ─────────────────────────────────────────────────────
  String get myContributions => _km ? 'ការចូលរួមរបស់ខ្ញុំ' : 'My Contributions';
  String contributionsCount(int n) => _km ? '$n ការចូលរួម' : '$n contributions';
  String get communityContributor =>
      _km ? 'អ្នកចូលរួមរបស់សហគមន៍' : 'Community contributor';
  String get contributionTypesLine => _km
      ? 'ការវាយតម្លៃ · មតិ · រូបភាព · ទីកន្លែងថ្មី'
      : 'Ratings · Comments · Photos · New places';
  String get statAverage => _km ? 'មធ្យម' : 'Average';
  String get photos => _km ? 'រូបភាព' : 'Photos';
  String get statNewPlaces => _km ? 'ទីកន្លែងថ្មី' : 'New places';
  String get contributionSaved =>
      _km ? 'ការចូលរួមត្រូវបានរក្សាទុក' : 'Contribution saved';
  String get placeRequestSubmitted => _km
      ? 'បានផ្ញើសំណើ — រង់ចាំការអនុម័តពីអ្នកគ្រប់គ្រង'
      : 'Request sent — waiting for admin approval';
  String get myPlaceRequests => _km ? 'សំណើទីកន្លែងរបស់ខ្ញុំ' : 'My place requests';
  String get tapOrLongPressToMove => _km
      ? 'ប៉ះ ឬ ចុចឲ្យជាប់លើផែនទីដើម្បីផ្លាស់ប្ដូរទីតាំង'
      : 'Tap or long-press the map to move the location';
  String get contributionUpdated =>
      _km ? 'ការចូលរួមត្រូវបានធ្វើបច្ចុប្បន្នភាព' : 'Contribution updated';
  String contributionRemoved(String name) =>
      _km ? 'បានលុបការចូលរួម «$name»' : 'Removed contribution "$name"';
  String get clearAllContributionsTitle =>
      _km ? 'លុបការចូលរួមទាំងអស់?' : 'Remove all contributions?';
  String clearAllContributionsBody(int n) => _km
      ? 'ការចូលរួមទាំង $n នឹងត្រូវបានយកចេញ។'
      : 'All $n contributions will be removed.';
  String get allContributionsCleared =>
      _km ? 'បានលុបការចូលរួមទាំងអស់' : 'All contributions removed';
  String get couldNotLoadContributions =>
      _km ? 'មិនអាចទាញយកការចូលរួមបានទេ' : 'Could not load contributions';
  String get noContributionsYet =>
      _km ? 'មិនទាន់មានការចូលរួម' : 'No contributions yet';
  String get noContributionsHint => _km
      ? 'ផ្ដល់ការវាយតម្លៃ មតិយោបល់ ឬរូបភាពអំពីទីកន្លែងមួយ ដើម្បីជួយសហគមន៍។'
      : 'Add a rating, comment, or photos for a place to help the community.';
  String get contributeNow => _km ? 'ចូលរួមឥឡូវ' : 'Contribute now';
  String get noContributionsInCategory =>
      _km ? 'គ្មានការចូលរួមក្នុងប្រភេទនេះ' : 'No contributions in this category';

  // Contribution form.
  String get couldNotPickImage =>
      _km ? 'មិនអាចជ្រើសរូបភាពបានទេ' : 'Could not pick an image';
  String get locationUnknownYet =>
      _km ? 'មិនទាន់ដឹងទីតាំងអ្នកទេ' : 'Your location is not known yet';
  String get pleaseProvideRating =>
      _km ? 'សូមផ្ដល់ការវាយតម្លៃ' : 'Please provide a rating';
  String get pleaseSelectPlace =>
      _km ? 'សូមជ្រើសទីកន្លែងមួយ' : 'Please select a place';
  String get pleaseSetLocation => _km ? 'សូមកំណត់ទីតាំង' : 'Please set a location';
  String get saveFailedTryAgain =>
      _km ? 'រក្សាទុកមិនបាន — សូមព្យាយាមម្ដងទៀត' : 'Save failed — please try again';
  String get comments => _km ? 'មតិយោបល់' : 'Comments';
  String photosCount(int n) => _km ? 'រូបភាព ($n)' : 'Photos ($n)';
  String get editContribution => _km ? 'កែសម្រួលការចូលរួម' : 'Edit contribution';
  String get newContribution => _km ? 'ការចូលរួមថ្មី' : 'New contribution';
  String get rateTab => _km ? 'វាយតម្លៃ' : 'Rate';
  String get createNewTab => _km ? 'បង្កើតថ្មី' : 'Create new';
  String get selectPlace => _km ? 'ជ្រើសទីកន្លែង' : 'Select a place';
  String get nameInKhmerLabel => _km ? 'ឈ្មោះជាភាសាខ្មែរ' : 'Name in Khmer';
  String get nameKhmerHint => _km ? 'ឧ. កាហ្វេ​ស្រែ​ខ្មែរ' : 'e.g. Srae Khmer Cafe';
  String get pleaseEnterName => _km ? 'សូមបញ្ចូលឈ្មោះ' : 'Please enter a name';
  String get nameInLatinLabel => _km ? 'ឈ្មោះជាអក្សរឡាតាំង' : 'Name in Latin';
  String get pleaseEnterLatinName =>
      _km ? 'សូមបញ្ចូលឈ្មោះជាអក្សរឡាតាំង' : 'Please enter the Latin name';
  String get noLocationYet => _km ? 'មិនទាន់មានទីតាំង' : 'No location yet';
  String get locationLabel => _km ? 'ទីតាំង' : 'Location';
  String get currentShort => _km ? 'បច្ចុប្បន្ន' : 'Current';
  String get commentFieldLabel =>
      _km ? 'សរសេរអ្វីៗអំពីទីកន្លែងនេះ' : 'Write something about this place';
  String get commentFieldHint => _km
      ? 'ឧ. បទពិសោធន៍ល្អ សេវាកម្មរហ័ស...'
      : 'e.g. great experience, fast service...';
  String get add => _km ? 'បន្ថែម' : 'Add';
  String get update => _km ? 'ធ្វើបច្ចុប្បន្នភាព' : 'Update';
  String get searchPlaceHint => _km ? 'ស្វែងរកទីកន្លែង' : 'Search places';
  String get placeNotFound => _km ? 'រកមិនឃើញទីកន្លែង' : 'No places found';

  // Contribution card / sheet.
  String get newBadge => _km ? 'ថ្មី' : 'New';
  String get deleteContribution => _km ? 'លុបការចូលរួម' : 'Delete contribution';
  String get yourRating => _km ? 'ការវាយតម្លៃរបស់អ្នក' : 'Your rating';
  String get categoryNewPlaceByYou => _km
      ? 'ប្រភេទ · ទីកន្លែងថ្មីបង្កើតដោយអ្នក'
      : 'Category · New place created by you';
  String get contributionStatus => _km ? 'ស្ថានភាពចូលរួម' : 'Contribution status';

  /// Relative "added N ago" label for contributions.
  String addedAgo(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays >= 365) {
      final n = diff.inDays ~/ 365;
      return _km ? 'បានបន្ថែម $n ឆ្នាំមុន' : 'Added $n year(s) ago';
    }
    if (diff.inDays >= 30) {
      final n = diff.inDays ~/ 30;
      return _km ? 'បានបន្ថែម $n ខែមុន' : 'Added $n month(s) ago';
    }
    if (diff.inDays >= 7) {
      final n = diff.inDays ~/ 7;
      return _km ? 'បានបន្ថែម $n សប្ដាហ៍មុន' : 'Added $n week(s) ago';
    }
    if (diff.inDays >= 1) {
      return _km
          ? 'បានបន្ថែម ${diff.inDays} ថ្ងៃមុន'
          : 'Added ${diff.inDays} day(s) ago';
    }
    if (diff.inHours >= 1) {
      return _km
          ? 'បានបន្ថែម ${diff.inHours} ម៉ោងមុន'
          : 'Added ${diff.inHours} hour(s) ago';
    }
    if (diff.inMinutes >= 1) {
      return _km
          ? 'បានបន្ថែម ${diff.inMinutes} នាទីមុន'
          : 'Added ${diff.inMinutes} minute(s) ago';
    }
    return _km ? 'បានបន្ថែមអម្បាញ់មិញ' : 'Added just now';
  }

  // Relative "saved N ago" labels.
  String savedAgo(DateTime savedAt) {
    final diff = DateTime.now().difference(savedAt);
    if (diff.inDays >= 365) {
      final n = diff.inDays ~/ 365;
      return _km ? 'បានរក្សាទុក $n ឆ្នាំមុន' : 'Saved $n year(s) ago';
    }
    if (diff.inDays >= 30) {
      final n = diff.inDays ~/ 30;
      return _km ? 'បានរក្សាទុក $n ខែមុន' : 'Saved $n month(s) ago';
    }
    if (diff.inDays >= 7) {
      final n = diff.inDays ~/ 7;
      return _km ? 'បានរក្សាទុក $n សប្ដាហ៍មុន' : 'Saved $n week(s) ago';
    }
    if (diff.inDays >= 1) {
      return _km
          ? 'បានរក្សាទុក ${diff.inDays} ថ្ងៃមុន'
          : 'Saved ${diff.inDays} day(s) ago';
    }
    if (diff.inHours >= 1) {
      return _km
          ? 'បានរក្សាទុក ${diff.inHours} ម៉ោងមុន'
          : 'Saved ${diff.inHours} hour(s) ago';
    }
    if (diff.inMinutes >= 1) {
      return _km
          ? 'បានរក្សាទុក ${diff.inMinutes} នាទីមុន'
          : 'Saved ${diff.inMinutes} minute(s) ago';
    }
    return _km ? 'បានរក្សាទុកអម្បាញ់មិញ' : 'Saved just now';
  }
}
