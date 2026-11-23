/// What kind of thing a receipt line names, as far as the dictionary knows.
enum ItemKind {
  drink,
  food,

  /// Packaging, service and option wording ("VASO DESECHABLE", "PARA
  /// LLEVAR", "MINERAL"): neither food nor drink on its own.
  other,
}

/// How a dictionary entry behaves when the English line is put together.
enum _Role {
  /// A thing that can be ordered: "jugo", "taco", "latte".
  head,

  /// A flavour or ingredient: "naranja", "queso". Goes in front of a head
  /// ("jugo de naranja" -> "orange juice"), stands alone otherwise.
  ingredient,

  /// A brand, kept as printed: "Nutella", "Coca-Cola".
  brand,

  /// Goes in front of what it describes: "entera" -> "whole milk".
  adjective,

  /// Stays behind what it describes: "al gusto" -> "eggs any style".
  after,

  /// Goes to the end after a comma: "CH" -> ", small".
  size,

  /// A container or portion: "orden de papas" -> "order of fries".
  measure,

  /// Opens an option line: "cambio a" -> "Change to ...".
  lead,
}

class _Entry {
  const _Entry(
    this.key,
    this.english,
    this.plural,
    this.role,
    this.kind, {
    this.asPrinted = false,
  });

  /// The Spanish wording this entry was written for.
  final String key;
  final String english;

  /// English for more than one; null when the usual "-s" rule applies.
  final String? plural;
  final _Role role;
  final ItemKind kind;

  /// English or international wording, already in English word order.
  final bool asPrinted;

  bool sameMeaning(_Entry other) =>
      english == other.english && role == other.role && kind == other.kind;
}

class _Hit {
  const _Hit(this.entry, this.plural, this.derived);
  final _Entry entry;
  final bool plural;

  /// Made by a rule (plural, feminine, "de" left out), not written down.
  final bool derived;
}

enum _T { word, number, quantity, slash }

class _Token {
  _Token(this.type, this.text, this.raw, {this.changed = false});
  final _T type;

  /// Lower-case, no accents; for a quantity the tidy English ("20 g").
  String text;

  /// As printed.
  final String raw;

  /// Rewritten by a rule (abbreviation written out, read error repaired).
  bool changed;
}

enum _U { entry, number, quantity, letter, connector, unknown }

class _Unit {
  _Unit(this.type, this.text, {this.entry, this.plural = false});
  final _U type;

  /// English for a number, quantity or letter; the Spanish connector.
  final String text;
  _Entry? entry;
  final bool plural;

  /// Joined to the unit before it by "de".
  bool linked = false;

  /// Joined to the unit before it by "y" inside one name.
  bool joined = false;

  /// "MEDIA" read as the size medium: only safe on a drink.
  bool needsDrink = false;

  _Role? get role => entry?.role;
  bool get isNumber => type == _U.number || type == _U.quantity;
  bool get isNoun =>
      role == _Role.head || role == _Role.ingredient || role == _Role.brand;

  String get singular => entry?.english ?? text;
  String get english => entry == null
      ? text
      : (plural ? ItemLexicon._pluralOf(entry!) : entry!.english);
}

/// A built-in dictionary for the wording tills print for food and drink, so
/// common items never depend on the on-device translation model (which reads
/// "MALTEADA C CHOCOLATE CH" as "Misted C Chocolate CH", "COLA" as "queue"
/// and "PAPAS" as "popes").
///
/// [translate] answers only when every word of the line is understood;
/// anything else is left to the model and the user.
class ItemLexicon {
  ItemLexicon._();

  // ------------------------------------------------------------- the words

  /// Drinks named in Spanish.
  static const Map<String, String> _drinks = {
    'agua': 'water',
    'agua natural': 'still water',
    'agua con gas': 'sparkling water',
    'agua sin gas': 'still water',
    'agua gasificada': 'sparkling water',
    'agua de sabor': 'flavoured water',
    'agua del dia': 'flavoured water of the day',
    'agua fresca': 'agua fresca (fruit drink)',
    'agua de horchata': 'horchata (rice drink)',
    'agua quina': 'tonic water',
    'agua tonica': 'tonic water',
    'agua de panela': 'aguapanela (sugar-cane drink)',
    'aguapanela': 'aguapanela (sugar-cane drink)',
    'jugo': 'juice',
    'zumo': 'juice',
    'nectar': 'nectar',
    'limonada': 'lemonade',
    'limonada natural': 'still lemonade',
    'naranjada': 'orangeade',
    'naranjada natural': 'still orangeade',
    'licuado': 'smoothie',
    'batido': 'shake',
    'malteada': 'milkshake',
    'merengada': 'milkshake',
    'refresco': 'soft drink',
    'gaseosa': 'soft drink',
    'bebida': 'drink',
    // Guatemala and El Salvador: "FRESCO DE TAMARINDO" is a fruit drink.
    'fresco de': 'drink',
    'cafe': 'coffee',
    'cafe de olla': 'café de olla (spiced coffee)',
    'cafe latte': 'latte',
    'cafe capuchino': 'cappuccino',
    'cafe cappuccino': 'cappuccino',
    'cafe expreso': 'espresso',
    'cafe espresso': 'espresso',
    'cafe expresso': 'espresso',
    'cafe cortado': 'cortado',
    'cafe del dia': 'coffee of the day',
    'cafe tinto': 'black coffee',
    'cafe lechero': 'café lechero (milky coffee)',
    'te': 'tea',
    'te chai': 'chai tea',
    'te chai latte': 'chai tea latte',
    'tisana': 'herbal tea',
    'infusion': 'herbal tea',
    'aromatica': 'herbal tea',
    'chocolate caliente': 'hot chocolate',
    'chocolate frio': 'cold chocolate',
    'chocomilk': 'chocolate milk',
    'choco milk': 'chocolate milk',
    'leche': 'milk',
    'cerveza': 'beer',
    'chela': 'beer',
    'cerveza de barril': 'draught beer',
    'cerveza clara': 'lager',
    'vino': 'wine',
    'vino tinto': 'red wine',
    'vino rosado': 'rosé wine',
    'vino espumoso': 'sparkling wine',
    'copa de tinto': 'glass of red wine',
    'botella de tinto': 'bottle of red wine',
    'ron': 'rum',
    'ginebra': 'gin',
    'licor': 'liqueur',
    'coctel': 'cocktail',
    'trago': 'drink',
    'digestivo': 'digestif',
    'aperitivo': 'aperitif',
    'malta': 'malt drink',
    'cebada': 'barley drink',
    'bebida energetica': 'energy drink',
    'bebida energizante': 'energy drink',
    'bebida hidratante': 'sports drink',
  };

  /// Drinks whose name is not translated: the name is the English.
  static const Map<String, String> _drinksKept = {
    'horchata': 'horchata',
    'michelada': 'michelada',
    'chelada': 'chelada',
    'paloma': 'paloma',
    'margarita': 'margarita',
    'mojito': 'mojito',
    'cuba libre': 'cuba libre',
    'pina colada': 'piña colada',
    'sangria': 'sangria',
    'tinto de verano': 'tinto de verano',
    'tepache': 'tepache',
    'pulque': 'pulque',
    'tejate': 'tejate',
    'tejuino': 'tejuino',
    'pozol': 'pozol',
    'tascalate': 'tascalate',
    'carajillo': 'carajillo',
    'cantarito': 'cantarito',
    'clericot': 'clericot',
    'mezcal': 'mezcal',
    'tequila': 'tequila',
    'vodka': 'vodka',
    'whisky': 'whisky',
    'whiskey': 'whiskey',
    'brandy': 'brandy',
    'aguardiente': 'aguardiente',
    'pisco sour': 'pisco sour',
    'caipirinha': 'caipirinha',
    'daiquiri': 'daiquiri',
    'martini': 'martini',
    'negroni': 'negroni',
    'mimosa': 'mimosa',
    'bloody mary': 'bloody mary',
    'gin tonic': 'gin and tonic',
    'aperol spritz': 'Aperol spritz',
    'spritz': 'spritz',
    'kombucha': 'kombucha',
    'mangonada': 'mangonada',
    'chamoyada': 'chamoyada',
    'champurrado': 'champurrado (chocolate atole)',
    'atole': 'atole (hot corn drink)',
    'atol': 'atol (hot corn drink)',
    'atol de elote': 'atol de elote (hot sweetcorn drink)',
    'atol shuco': 'atol shuco',
    'rompope': 'rompope (egg liqueur)',
    'chicha': 'chicha',
    'tizana': 'tizana (fruit punch)',
    'papelon con limon': 'papelón con limón (sugar-cane limeade)',
    'horchata de morro': 'horchata de morro',
    'guayoyo': 'guayoyo (black coffee)',
    'marron': 'marrón (coffee with milk)',
  };

  /// Drinks printed in English or under their international name.
  static const Map<String, String> _drinksAsPrinted = {
    'latte': 'latte',
    'espresso': 'espresso',
    'expresso': 'espresso',
    'expreso': 'espresso',
    'cappuccino': 'cappuccino',
    'capuchino': 'cappuccino',
    'capuccino': 'cappuccino',
    'cappuchino': 'cappuccino',
    'cappucino': 'cappuccino',
    'capucino': 'cappuccino',
    'macchiato': 'macchiato',
    'machiato': 'macchiato',
    'americano': 'americano',
    'frappe': 'frappe',
    'frape': 'frappe',
    'frappuccino': 'Frappuccino',
    'frapuccino': 'Frappuccino',
    'frappucino': 'Frappuccino',
    'cortado': 'cortado',
    'affogato': 'affogato',
    'ristretto': 'ristretto',
    'lungo': 'lungo',
    'doppio': 'doppio',
    'smoothie': 'smoothie',
    'shake': 'shake',
    'milkshake': 'milkshake',
    'cold brew': 'cold brew',
    'flat white': 'flat white',
    'iced whip': 'iced whip',
    'coffee': 'coffee',
    'tea': 'tea',
    'juice': 'juice',
    'water': 'water',
    'soda': 'soda',
    'beer': 'beer',
    'wine': 'wine',
    'lemonade': 'lemonade',
    'hot chocolate': 'hot chocolate',
    'dirty chai': 'dirty chai',
    'drink': 'drink',
    'cocktail': 'cocktail',
    'mocktail': 'mocktail',
    'cola': 'cola',
  };

  /// Dishes and courses named in Spanish.
  static const Map<String, String> _dishes = {
    'desayuno': 'breakfast',
    'almuerzo': 'lunch',
    'comida': 'meal',
    'cena': 'dinner',
    'comida corrida': 'set lunch',
    'menu del dia': 'set menu of the day',
    'menu ejecutivo': 'set lunch',
    'menu': 'menu',
    'paquete': 'package',
    'platillo': 'dish',
    'plato': 'plate',
    'plato fuerte': 'main course',
    'entrada': 'starter',
    'guarnicion': 'side dish',
    'complemento': 'side',
    'botana': 'snack',
    'postre': 'dessert',
    'sopa': 'soup',
    'sopa azteca': 'tortilla soup',
    'caldo': 'soup',
    'consome': 'consommé',
    'crema de champinones': 'cream of mushroom soup',
    'crema de elote': 'cream of corn soup',
    'crema de brocoli': 'cream of broccoli soup',
    'crema de zanahoria': 'cream of carrot soup',
    'crema de calabaza': 'cream of squash soup',
    'crema de espinaca': 'cream of spinach soup',
    'crema de espinacas': 'cream of spinach soup',
    'crema de tomate': 'cream of tomato soup',
    'crema de esparragos': 'cream of asparagus soup',
    'crema de chile poblano': 'cream of poblano pepper soup',
    'crema de frijol': 'cream of bean soup',
    'crema de papa': 'cream of potato soup',
    'crema de verduras': 'cream of vegetable soup',
    'crema de pollo': 'cream of chicken soup',
    'ensalada': 'salad',
    'hamburguesa': 'burger',
    'emparedado': 'sandwich',
    'sanduche': 'sandwich',
    'torta': 'sandwich',
    'torta de pierna': 'roast pork sandwich',
    'pan': 'bread',
    'pan dulce': 'sweet bread',
    'pan tostado': 'toast',
    'pan de caja': 'sliced bread',
    'pan arabe': 'pitta bread',
    'pan pita': 'pitta bread',
    'pan pizza': 'pan pizza',
    'pan de chocolate': 'pain au chocolat',
    'chocolatin': 'pain au chocolat',
    'cuernito': 'croissant',
    'cuerno': 'croissant',
    'dona': 'doughnut',
    'galleta': 'cookie',
    'galleta salada': 'cracker',
    'pastel': 'cake',
    'pay': 'pie',
    'pay de queso': 'cheesecake',
    'tarta': 'tart',
    'flan': 'flan',
    'gelatina': 'jelly',
    'helado': 'ice cream',
    'copa de helado': 'ice cream sundae',
    'nieve': 'sorbet',
    'paleta': 'ice pop',
    'paleta helada': 'ice pop',
    'raspado': 'shaved ice',
    'crepa': 'crepe',
    'rol de canela': 'cinnamon roll',
    'rollo de canela': 'cinnamon roll',
    'panque': 'pound cake',
    'arroz con leche': 'rice pudding',
    'coctel de frutas': 'fruit cocktail',
    'coctel de camaron': 'shrimp cocktail',
    'coctel de camarones': 'shrimp cocktail',
    'hot cakes': 'pancakes',
    'hotcakes': 'pancakes',
    'hot cake': 'pancake',
    'pancake': 'pancake',
    'panqueque': 'pancake',
    'omelette': 'omelette',
    'omelet': 'omelette',
    'tortilla espanola': 'Spanish omelette',
    'filete': 'fillet',
    'pechuga': 'chicken breast',
    'pechuga de pollo': 'chicken breast',
    'pechuga de pavo': 'turkey breast',
    'milanesa de pollo': 'chicken milanesa',
    'milanesa de res': 'beef milanesa',
    'bistec': 'steak',
    'bisteck': 'steak',
    'bistek': 'steak',
    'bife': 'steak',
    'chuleta': 'chop',
    'costilla': 'rib',
    'alitas': 'wings',
    'pierna': 'leg',
    'muslo': 'thigh',
    'pierna de pollo': 'chicken leg',
    'lomo': 'loin',
    'albondigas': 'meatballs',
    'brocheta': 'skewer',
    'parrillada': 'mixed grill',
    'carne asada': 'carne asada (grilled beef)',
    'carnes frias': 'cold cuts',
    'pure de papa': 'mashed potato',
    'pure': 'mashed potato',
    'papas fritas': 'fries',
    'papas a la francesa': 'french fries',
    'papas francesas': 'french fries',
    'papas francesa': 'french fries',
    'papas gajo': 'potato wedges',
    'papas en gajo': 'potato wedges',
    'papas en gajos': 'potato wedges',
    'platano frito': 'fried plantain',
    'platano macho': 'plantain',
    'tajadas': 'fried plantain slices',
    'frijoles refritos': 'refried beans',
    'frijoles charros': 'charro beans',
    'frijoles de la olla': 'pot beans',
    'frijoles volteados': 'refried black beans',
    'salsa': 'sauce',
    'salsa inglesa': 'Worcestershire sauce',
    'aderezo': 'dressing',
    'cereal': 'cereal',
    'yogurt': 'yogurt',
    'yogur': 'yogurt',
    'yoghurt': 'yogurt',
    'yogurt natural': 'plain yogurt',
    'fruta': 'fruit|fruit',
    'lasana': 'lasagne',
    'espagueti': 'spaghetti',
    'perro caliente': 'hot dog',
    'palomitas': 'popcorn',
    'tres leches': 'tres leches cake',
    'pastel de tres leches': 'tres leches cake',
    'pastel tres leches': 'tres leches cake',
    'dulce de leche': 'dulce de leche',
    'mazorca': 'corn on the cob',
    'tortilla': 'tortilla',
    'totopos': 'tortilla chips',
    'mariscos': 'seafood',
    'verduras': 'vegetables',
    'vegetales': 'vegetables',
    'ingrediente': 'ingredient',
  };

  /// Dishes that must not be translated word for word ("al pastor" is not
  /// "shepherd-style"): the name is kept, with the right accents.
  static const Map<String, String> _dishesKept = {
    'taco': 'taco',
    'taco al pastor': 'taco al pastor|tacos al pastor',
    'taco de canasta': 'taco de canasta|tacos de canasta',
    'taco arabe': 'taco árabe|tacos árabes',
    'quesadilla': 'quesadilla',
    'burrito': 'burrito',
    'enchilada': 'enchilada',
    'enchilada suiza': 'enchilada suiza|enchiladas suizas',
    'sope': 'sope',
    'gordita': 'gordita',
    'tlacoyo': 'tlacoyo',
    'huarache': 'huarache',
    'tlayuda': 'tlayuda',
    'pambazo': 'pambazo',
    'tamal': 'tamal|tamales',
    'flauta': 'flauta',
    'chalupa': 'chalupa',
    'memela': 'memela',
    'panucho': 'panucho',
    'salbute': 'salbute',
    'gringa': 'gringa',
    'sincronizada': 'sincronizada',
    'alambre': 'alambre',
    'fajitas': 'fajitas',
    'chilaquiles': 'chilaquiles',
    'enfrijoladas': 'enfrijoladas',
    'entomatadas': 'entomatadas',
    'enmoladas': 'enmoladas',
    'molletes': 'molletes',
    'mole': 'mole',
    'pozole': 'pozole',
    'menudo': 'menudo',
    'pancita': 'pancita',
    'birria': 'birria',
    'barbacoa': 'barbacoa',
    'carnitas': 'carnitas',
    'cochinita': 'cochinita pibil',
    'cochinita pibil': 'cochinita pibil',
    'chicharron': 'chicharrón',
    'chile relleno': 'chile relleno|chiles rellenos',
    'chiles en nogada': 'chiles en nogada',
    'esquites': 'esquites',
    'nachos': 'nachos',
    'guacamole': 'guacamole',
    'guacamol': 'guacamole',
    'pico de gallo': 'pico de gallo',
    'ceviche': 'ceviche',
    'cebiche': 'ceviche',
    'aguachile': 'aguachile',
    'tostada': 'tostada',
    'torta ahogada': 'torta ahogada',
    'torta cubana': 'torta cubana',
    'huevos rancheros': 'huevos rancheros',
    'huevos divorciados': 'huevos divorciados',
    'huevos motulenos': 'huevos motuleños',
    'huevos pericos': 'huevos pericos',
    'machaca': 'machaca',
    'tinga': 'tinga',
    'caldo tlalpeno': 'caldo tlalpeño',
    'sopa de lima': 'sopa de lima (lime soup)',
    'milanesa': 'milanesa',
    'papas bravas': 'papas bravas',
    'quesabirria': 'quesabirria',
    'queso fundido': 'queso fundido',
    'choriqueso': 'choriqueso',
    'pan de muerto': 'pan de muerto',
    'concha': 'concha (sweet bread)',
    'bolillo': 'bolillo (bread roll)',
    'telera': 'telera (bread roll)',
    'bisquet': 'bisquet (scone)',
    'mantecada': 'mantecada (muffin)',
    'churro': 'churro',
    'bunuelo': 'buñuelo',
    'empanada': 'empanada',
    'paste': 'paste (pasty)',
    'chocoflan': 'chocoflan',
    'flan napolitano': 'flan napolitano',
    'cecina': 'cecina (salted beef)',
    'tasajo': 'tasajo (dried beef)',
    'picadillo': 'picadillo',
    'suadero': 'suadero',
    // El Salvador
    'pupusa': 'pupusa',
    'pupusa revuelta': 'pupusa revuelta|pupusas revueltas',
    'curtido': 'curtido (pickled cabbage)',
    'casamiento': 'casamiento (rice and beans)',
    'pan con pollo': 'pan con pollo (chicken sandwich)',
    'panes con pollo': 'panes con pollo (chicken sandwiches)',
    // Venezuela
    'arepa': 'arepa',
    'cachapa': 'cachapa',
    'tequeno': 'tequeño',
    'pabellon': 'pabellón criollo',
    'pabellon criollo': 'pabellón criollo',
    'hallaca': 'hallaca',
    'cachito': 'cachito (ham roll)',
    'patacon': 'patacón|patacones',
    'tostones': 'tostones (fried plantain)',
    'golfeado': 'golfeado (sticky bun)',
    // Guatemala
    'pepian': 'pepián',
    'kak ik': "kak'ik",
    'kakik': "kak'ik",
    'jocon': 'jocón',
    'hilachas': 'hilachas',
    'revolcado': 'revolcado',
    'subanik': 'subanik',
    'tapado': 'tapado',
    'chuchito': 'chuchito',
    'rellenitos': 'rellenitos',
    'garnacha': 'garnacha',
    'shuco': 'shuco',
    'desayuno chapin': 'desayuno chapín (Guatemalan breakfast)',
    'mosh': 'mosh (oat porridge)',
    'churrasco': 'churrasco',
    // Colombia
    'bandeja paisa': 'bandeja paisa',
    'ajiaco': 'ajiaco',
    'sancocho': 'sancocho',
    'pandebono': 'pandebono',
    'almojabana': 'almojábana',
    'calentado': 'calentado',
    'salchipapa': 'salchipapa',
    'choripan': 'choripán|choripanes',
  };

  /// Food printed in English or under its international name.
  static const Map<String, String> _dishesAsPrinted = {
    'sandwich': 'sandwich',
    'sandwitch': 'sandwich',
    'club sandwich': 'club sandwich',
    'sandwich club': 'club sandwich',
    'pizza': 'pizza',
    'pasta': 'pasta',
    'lasagna': 'lasagne',
    'spaghetti': 'spaghetti',
    'bagel': 'bagel',
    'croissant': 'croissant',
    'croisant': 'croissant',
    'panini': 'panini',
    'baguette': 'baguette',
    'baguete': 'baguette',
    'ciabatta': 'ciabatta',
    'chapata': 'ciabatta',
    'focaccia': 'focaccia',
    'brioche': 'brioche',
    'brownie': 'brownie',
    'cheesecake': 'cheesecake',
    'muffin': 'muffin',
    'cupcake': 'cupcake',
    'donut': 'doughnut',
    'cookie': 'cookie',
    'waffle': 'waffle',
    'wafle': 'waffle',
    'burger': 'burger',
    'cheeseburger': 'cheeseburger',
    'hot dog': 'hot dog',
    'hotdog': 'hot dog',
    'nuggets': 'nuggets',
    'wrap': 'wrap',
    'bowl': 'bowl',
    'salad': 'salad',
    'toast': 'toast',
    'roll': 'roll',
    'pie': 'pie',
    'cake': 'cake',
    'sundae': 'sundae',
    'combo': 'combo',
    'buffet': 'buffet',
    'sushi': 'sushi',
    'ramen': 'ramen',
    'tenders': 'tenders',
    'strips': 'strips',
    'wings': 'wings',
    'boneless': 'boneless wings',
    'fries': 'fries',
    'french fries': 'french fries',
    'snack': 'snack',
    'dip': 'dip',
    'ice cream': 'ice cream',
    'rib eye': 'rib-eye steak',
    'ribeye': 'rib-eye steak',
    't bone': 'T-bone steak',
    'tbone': 'T-bone steak',
    'new york': 'New York strip steak',
    'sirloin': 'sirloin steak',
    'big mac': 'Big Mac',
    'whopper': 'Whopper',
    'mcpollo': 'McPollo',
    'mcnuggets': 'McNuggets',
    'mcflurry': 'McFlurry',
    'cajita feliz': 'Happy Meal',
  };

  /// Ingredients and flavours.
  static const Map<String, String> _ingredients = {
    'queso': 'cheese',
    'queso crema': 'cream cheese',
    'queso fresco': 'queso fresco',
    'queso de mano': 'queso de mano',
    'jamon': 'ham',
    'tocino': 'bacon',
    'tocineta': 'bacon',
    'salchicha': 'sausage',
    'chorizo': 'chorizo',
    'longaniza': 'longaniza',
    'chistorra': 'chistorra',
    'morcilla': 'blood sausage',
    'salami': 'salami',
    'pepperoni': 'pepperoni',
    'peperoni': 'pepperoni',
    'pollo': 'chicken',
    'gallina': 'hen',
    'res': 'beef',
    'carne de res': 'beef',
    'carne': 'meat',
    'carne molida': 'minced beef',
    'cerdo': 'pork',
    'puerco': 'pork',
    'pernil': 'roast pork',
    'lechon': 'suckling pig',
    'pavo': 'turkey',
    'cordero': 'lamb',
    'borrego': 'lamb',
    'ternera': 'veal',
    'pato': 'duck',
    'conejo': 'rabbit',
    'arrachera': 'skirt steak',
    'lengua': 'tongue',
    'pescado': 'fish|fish',
    'camaron': 'shrimp|shrimp',
    'pulpo': 'octopus',
    'calamar': 'squid|squid',
    'atun': 'tuna',
    'salmon': 'salmon',
    'tilapia': 'tilapia',
    'mojarra': 'mojarra',
    'huachinango': 'red snapper',
    'robalo': 'sea bass',
    'marisco': 'seafood',
    'jaiba': 'crab',
    'cangrejo': 'crab',
    'langosta': 'lobster',
    'cola de langosta': 'lobster tail',
    'langostino': 'king prawn',
    'ostion': 'oyster',
    'almeja': 'clam',
    'mejillon': 'mussel',
    'surimi': 'surimi',
    'huevo': 'egg',
    'arroz': 'rice',
    'frijol': 'bean',
    'lenteja': 'lentil',
    'garbanzo': 'chickpea',
    'elote': 'corn',
    'maiz': 'corn',
    'harina': 'flour',
    'trigo': 'wheat',
    'avena': 'oat',
    'granola': 'granola',
    'fideo': 'noodle',
    'papa': 'potato|potatoes',
    'camote': 'sweet potato|sweet potatoes',
    'yuca': 'cassava',
    // "LICUADO DE PLATANO" is banana; a side of "PLATANOS" is plantains.
    'platano': 'banana|plantains',
    'banano': 'banana',
    'banana': 'banana',
    'verdura': 'vegetable',
    'vegetal': 'vegetable',
    'lechuga': 'lettuce',
    'jitomate': 'tomato|tomatoes',
    'tomate': 'tomato|tomatoes',
    'cebolla': 'onion',
    'ajo': 'garlic',
    'chile': 'chilli|chillies',
    'jalapeno': 'jalapeño',
    'habanero': 'habanero',
    'chipotle': 'chipotle',
    'rajas': 'poblano pepper strips',
    'aguacate': 'avocado',
    'champinon': 'mushroom',
    'hongo': 'mushroom',
    'seta': 'mushroom',
    'espinaca': 'spinach|spinach',
    'brocoli': 'broccoli',
    'coliflor': 'cauliflower',
    'zanahoria': 'carrot',
    'calabaza': 'squash',
    'calabacita': 'courgette',
    'flor de calabaza': 'squash blossom',
    'huitlacoche': 'huitlacoche',
    'nopal': 'nopal|nopales',
    'pepino': 'cucumber',
    'apio': 'celery',
    'betabel': 'beetroot',
    'pimiento': 'pepper',
    'ejote': 'green bean',
    'chicharo': 'pea',
    'esparrago': 'asparagus|asparagus',
    'aceituna': 'olive',
    'cilantro': 'coriander',
    'perejil': 'parsley',
    'albahaca': 'basil',
    'hierbabuena': 'mint',
    'menta': 'mint',
    'loroco': 'loroco',
    'naranja': 'orange',
    'manzana': 'apple',
    'fresa': 'strawberry',
    'pina': 'pineapple',
    'mango': 'mango',
    'papaya': 'papaya',
    'sandia': 'watermelon',
    'melon': 'melon',
    'uva': 'grape',
    'durazno': 'peach',
    'melocoton': 'peach',
    'pera': 'pear',
    'guayaba': 'guava',
    'toronja': 'grapefruit',
    'mandarina': 'tangerine',
    // The small green "limón" of Mexico and Central America is a lime.
    'limon': 'lime',
    'coco': 'coconut',
    'tamarindo': 'tamarind',
    'jamaica': 'hibiscus',
    'rosa de jamaica': 'hibiscus',
    'maracuya': 'passion-fruit',
    'parchita': 'passion-fruit',
    'guanabana': 'soursop',
    'lulo': 'lulo',
    'tomate de arbol': 'tree tomato',
    'zarzamora': 'blackberry',
    'mora': 'blackberry',
    'frambuesa': 'raspberry',
    'frutos rojos': 'red berry',
    'cereza': 'cherry',
    'kiwi': 'kiwi',
    'higo': 'fig',
    'ciruela': 'plum',
    'mamey': 'mamey',
    'nuez': 'nut',
    'almendra': 'almond',
    'cacahuate': 'peanut',
    'mani': 'peanut',
    'avellana': 'hazelnut',
    'pistache': 'pistachio',
    'pistacho': 'pistachio',
    'ajonjoli': 'sesame',
    'chia': 'chia',
    'amaranto': 'amaranth',
    'soya': 'soy',
    'soja': 'soy',
    'azucar': 'sugar',
    'sal': 'salt',
    'pimienta': 'pepper',
    'canela': 'cinnamon',
    'vainilla': 'vanilla',
    'chocolate': 'chocolate',
    'cacao': 'cocoa',
    'cocoa': 'cocoa',
    'caramelo': 'caramel',
    'cajeta': 'cajeta (caramel)',
    'miel': 'honey',
    'maple': 'maple syrup',
    'miel de maple': 'maple syrup',
    'jarabe': 'syrup',
    'mermelada': 'jam',
    'mantequilla': 'butter',
    'margarina': 'margarine',
    'crema': 'cream',
    'crema batida': 'whipped cream',
    'crema acida': 'sour cream',
    'media crema': 'table cream',
    'crema de cacahuate': 'peanut butter',
    'crema de avellana': 'hazelnut spread',
    'crema de coco': 'coconut cream',
    'nata': 'cream',
    'lechera': 'condensed milk',
    'mayonesa': 'mayonnaise',
    'mayo': 'mayonnaise',
    'mostaza': 'mustard',
    'catsup': 'ketchup',
    'ketchup': 'ketchup',
    'vinagre': 'vinegar',
    'aceite': 'oil',
    'chamoy': 'chamoy',
    'moka': 'mocha',
    'moca': 'mocha',
    'te verde': 'green tea',
    'te negro': 'black tea',
    'manzanilla': 'chamomile',
    'jengibre': 'ginger',
    'curcuma': 'turmeric',
    'tofu': 'tofu',
  };

  /// Things that are neither food nor drink in English wording either.
  static const Map<String, String> _ingredientsOther = {
    'hielo': 'ice',
  };

  /// English and international flavour words, kept as printed.
  static const Map<String, String> _ingredientsAsPrinted = {
    'caramel': 'caramel',
    'vanilla': 'vanilla',
    'mocha': 'mocha',
    'chai': 'chai',
    'matcha': 'matcha',
    'taro': 'taro',
    'whip': 'whip',
    'chicken': 'chicken',
    'cheese': 'cheese',
    'bacon': 'bacon',
    'beef': 'beef',
    'pork': 'pork',
    'turkey': 'turkey',
    'egg': 'egg',
    'steak': 'steak',
    'mushroom': 'mushroom',
    'avocado': 'avocado',
    'strawberry': 'strawberry',
    'blueberry': 'blueberry',
    'cranberry': 'cranberry',
    'raspberry': 'raspberry',
    'berry': 'berry',
    'apple': 'apple',
    'orange': 'orange',
    'lemon': 'lemon',
    'peach': 'peach',
    'pineapple': 'pineapple',
    'coconut': 'coconut',
    'almond': 'almond',
    'oat': 'oat',
    'soy': 'soy',
    'honey': 'honey',
    'cinnamon': 'cinnamon',
    'cream': 'cream',
    'milk': 'milk',
    'ice': 'ice',
  };

  /// Drink brands, written the way the brand writes itself.
  static const Map<String, String> _drinkBrands = {
    'coca cola': 'Coca-Cola',
    'cocacola': 'Coca-Cola',
    'coca': 'Coca-Cola',
    'coke': 'Coke',
    'coca cola zero': 'Coca-Cola Zero',
    'coca zero': 'Coca-Cola Zero',
    'coca cola light': 'Coca-Cola Light',
    'coca light': 'Coca-Cola Light',
    'coca cola sin azucar': 'Coca-Cola Zero Sugar',
    'coca sin azucar': 'Coca-Cola Zero Sugar',
    'pepsi': 'Pepsi',
    'sprite': 'Sprite',
    'fanta': 'Fanta',
    'sidral': 'Sidral Mundet',
    'sidral mundet': 'Sidral Mundet',
    'manzanita sol': 'Manzanita Sol',
    'manzana lift': 'Manzana Lift',
    'squirt': 'Squirt',
    'mirinda': 'Mirinda',
    '7up': '7UP',
    'seven up': '7UP',
    'jarritos': 'Jarritos',
    'topo chico': 'Topo Chico',
    'penafiel': 'Peñafiel',
    'ciel': 'Ciel',
    'bonafont': 'Bonafont',
    'epura': 'Epura',
    'evian': 'Evian',
    'perrier': 'Perrier',
    'san pellegrino': 'San Pellegrino',
    'fuze tea': 'Fuze Tea',
    'boing': 'Boing',
    'jumex': 'Jumex',
    'del valle': 'Del Valle',
    'gatorade': 'Gatorade',
    'powerade': 'Powerade',
    'electrolit': 'Electrolit',
    'red bull': 'Red Bull',
    'monster': 'Monster',
    'yakult': 'Yakult',
    'nescafe': 'Nescafé',
    'clamato': 'Clamato',
    'corona': 'Corona',
    'modelo': 'Modelo',
    'modelo especial': 'Modelo Especial',
    'negra modelo': 'Negra Modelo',
    'victoria': 'Victoria',
    'pacifico': 'Pacífico',
    'tecate': 'Tecate',
    'indio': 'Indio',
    'dos equis': 'Dos Equis',
    'xx': 'Dos Equis',
    'bohemia': 'Bohemia',
    'heineken': 'Heineken',
    'stella artois': 'Stella Artois',
    'budweiser': 'Budweiser',
    'bud light': 'Bud Light',
    'michelob ultra': 'Michelob Ultra',
    'gallo': 'Gallo',
    'cabro': 'Cabro',
    'pilsener': 'Pilsener',
    'polar': 'Polar',
    'aguila': 'Águila',
    'club colombia': 'Club Colombia',
    'poker': 'Poker',
    'postobon': 'Postobón',
    'pony malta': 'Pony Malta',
    'maltin polar': 'Maltín Polar',
    'frescolita': 'Frescolita',
    'inca kola': 'Inca Kola',
    'kolashampan': 'Kolashampan',
    'salutaris': 'Salutaris',
    'don julio': 'Don Julio',
    'jose cuervo': 'José Cuervo',
    'bacardi': 'Bacardí',
    'havana club': 'Havana Club',
    'johnnie walker': 'Johnnie Walker',
    'absolut': 'Absolut',
    'smirnoff': 'Smirnoff',
    'baileys': 'Baileys',
    'kahlua': 'Kahlúa',
    'licor 43': 'Licor 43',
    'zacapa': 'Zacapa',
    'botran': 'Botran',
    'flor de cana': 'Flor de Caña',
    'santa teresa': 'Santa Teresa',
    'aperol': 'Aperol',
  };

  /// Food brands.
  static const Map<String, String> _foodBrands = {
    'nutella': 'Nutella',
    'oreo': 'Oreo',
    'kit kat': 'KitKat',
    'kitkat': 'KitKat',
    'mms': 'M&M\'s',
    'hershey': 'Hershey\'s',
    'hersheys': 'Hershey\'s',
    'philadelphia': 'Philadelphia',
    'sabritas': 'Sabritas',
    'doritos': 'Doritos',
    'cheetos': 'Cheetos',
    'ruffles': 'Ruffles',
    'takis': 'Takis',
    'tostitos': 'Tostitos',
    'pringles': 'Pringles',
    'gansito': 'Gansito',
    'kinder': 'Kinder',
    'ferrero': 'Ferrero',
    'snickers': 'Snickers',
    'lotus': 'Lotus',
    'biscoff': 'Biscoff',
    'tajin': 'Tajín',
    'valentina': 'Valentina',
    'tabasco': 'Tabasco',
  };

  /// Words that describe, and go in front in English. A word ending in "o"
  /// also covers its feminine ("frito", "frita").
  static const Map<String, String> _adjectives = {
    // milk
    'entero': 'whole',
    'deslactosado': 'lactose-free',
    'descremado': 'skimmed',
    'semidescremado': 'semi-skimmed',
    'light': 'light',
    'evaporado': 'evaporated',
    'condensado': 'condensed',
    'vegetal': 'plant-based',
    // water
    'mineral': 'sparkling',
    'natural': 'natural',
    'purificado': 'purified',
    'embotellado': 'bottled',
    // temperature
    'frio': 'cold',
    'caliente': 'hot',
    'tibio': 'warm',
    // preparation
    'asado': 'grilled',
    'rostizado': 'rotisserie',
    'frito': 'fried',
    'empanizado': 'breaded',
    'capeado': 'battered',
    'rebozado': 'battered',
    'dorado': 'crispy',
    'ahumado': 'smoked',
    'horneado': 'baked',
    'hervido': 'boiled',
    'cocido': 'boiled',
    'revuelto': 'scrambled',
    'estrellado': 'fried',
    'pochado': 'poached',
    'relleno': 'stuffed',
    'gratinado': 'au gratin',
    'adobado': 'marinated',
    'marinado': 'marinated',
    'desmenuzado': 'shredded',
    'deshebrado': 'shredded',
    'molido': 'minced',
    'rebanado': 'sliced',
    'picado': 'chopped',
    'batido': 'whipped',
    'a la plancha': 'grilled',
    'plancha': 'grilled',
    'a la parrilla': 'grilled',
    'a la brasa': 'char-grilled',
    'al carbon': 'charcoal-grilled',
    'al vapor': 'steamed',
    'al horno': 'baked',
    'a la lena': 'wood-fired',
    'a la mexicana': 'Mexican-style',
    'a la veracruzana': 'Veracruz-style',
    'a la tampiquena': 'Tampico-style',
    'a la poblana': 'Puebla-style',
    // option words
    'extra': 'extra',
    'adicional': 'additional',
    'doble': 'double',
    'triple': 'triple',
    'sencillo': 'single',
    'especial': 'special',
    'clasico': 'classic',
    'tradicional': 'traditional',
    'tipico': 'traditional',
    'original': 'original',
    'casero': 'homemade',
    'de la casa': 'house',
    'de temporada': 'seasonal',
    'mixto': 'mixed',
    'surtido': 'assorted',
    'completo': 'full',
    'vegetariano': 'vegetarian',
    'vegano': 'vegan',
    'integral': 'wholemeal',
    'organico': 'organic',
    'artesanal': 'artisan',
    'importado': 'imported',
    'nacional': 'domestic',
    'premium': 'premium',
    'gratis': 'free',
    'cortesia': 'complimentary',
    'de cortesia': 'complimentary',
    'sin alcohol': 'alcohol-free',
    'sin gluten': 'gluten-free',
    'descafeinado': 'decaf',
    'cargado': 'strong',
    'mini': 'mini',
    'junior': 'junior',
    'infantil': 'children\'s',
    'desechable': 'disposable',
    'retornable': 'returnable',
    'no retornable': 'non-returnable',
    'empleado': 'employee',
    // colours and tastes
    'blanco': 'white',
    'negro': 'black',
    'rojo': 'red',
    'verde': 'green',
    'amarillo': 'yellow',
    'azul': 'blue',
    'rosa': 'pink',
    'oscuro': 'dark',
    'dulce': 'sweet',
    'picante': 'spicy',
    'picoso': 'spicy',
    'suave': 'mild',
    'agridulce': 'sweet and sour',
    'fresco': 'fresh',
    'seco': 'dry',
    'tierno': 'tender',
    // origins and styles
    'mexicano': 'Mexican',
    'italiano': 'Italian',
    'frances': 'French',
    'francesa': 'French',
    'espanol': 'Spanish',
    'espanola': 'Spanish',
    'hawaiano': 'Hawaiian',
    'griego': 'Greek',
    'argentino': 'Argentinian',
    'cesar': 'Caesar',
    'ranchero': 'ranch-style',
    'norteno': 'northern-style',
    'poblano': 'poblano',
    'oaxaca': 'Oaxaca',
    'manchego': 'manchego',
    'chihuahua': 'Chihuahua',
    'cotija': 'cotija',
    'panela': 'panela',
    'gouda': 'gouda',
    'cheddar': 'cheddar',
    'mozzarella': 'mozzarella',
    'parmesano': 'parmesan',
    'serrano': 'serrano',
    'bbq': 'BBQ',
    'bufalo': 'buffalo',
    'buffalo': 'buffalo',
    'teriyaki': 'teriyaki',
    'ranch': 'ranch',
    'cajun': 'Cajun',
    'anejo': 'añejo',
    'reposado': 'reposado',
    'plata': 'silver',
    '4 quesos': 'four-cheese',
    'cuatro quesos': 'four-cheese',
    '3 quesos': 'three-cheese',
    'tres quesos': 'three-cheese',
  };

  /// English describing words, kept as printed.
  static const Map<String, String> _adjectivesAsPrinted = {
    'iced': 'iced',
    'hot': 'hot',
    'cold': 'cold',
    'crispy': 'crispy',
    'spicy': 'spicy',
    'grilled': 'grilled',
    'fried': 'fried',
    'classic': 'classic',
    'double': 'double',
    'single': 'single',
    'deluxe': 'deluxe',
    'club': 'club',
    'diet': 'diet',
    'red velvet': 'red velvet',
    'lemon pepper': 'lemon pepper',
    'honey mustard': 'honey mustard',
    'white': 'white',
    'dark': 'dark',
    'whole': 'whole',
    'skim': 'skimmed',
    'decaf': 'decaf',
  };

  /// Words that stay behind what they describe.
  static const Map<String, String> _after = {
    'al pastor': 'al pastor',
    'pastor': 'al pastor',
    'al gusto': 'any style',
    'para llevar': 'to go',
    'llevar': 'to go',
    'para aqui': 'to eat in',
    'comer aqui': 'to eat in',
    'para compartir': 'to share',
    'del dia': 'of the day',
    'al tiempo': 'at room temperature',
    'en las rocas': 'on the rocks',
    'derecho': 'neat',
    'al mojo de ajo': 'in garlic sauce',
    'al ajillo': 'in garlic sauce',
    'a la diabla': 'in spicy sauce',
    'al limon': 'with lime',
    'al natural': 'plain',
    'zero': 'Zero',
    'cero': 'Zero',
    'reina pepiada': 'reina pepiada',
    'pelua': 'pelúa',
    'domino': 'dominó',
    'con todo': 'with everything',
  };

  /// Sizes. A word ending in "o" also covers its feminine.
  static const Map<String, String> _sizes = {
    'chico': 'small',
    'pequeno': 'small',
    'mediano': 'medium',
    'grande': 'large',
    'extra grande': 'extra large',
    'extragrande': 'extra large',
    'xl': 'extra large',
    'jumbo': 'jumbo',
    'mega': 'mega',
    'familiar': 'family size',
    'individual': 'individual',
    'personal': 'personal',
    'regular': 'regular',
    'venti': 'venti',
    'alto': 'tall',
    'small': 'small',
    'medium': 'medium',
    'large': 'large',
    'tall': 'tall',
    'kids': 'kids',
    'litro': '1 litre',
    'medio litro': 'half litre',
    'medio kilo': 'half kilo',
    'kilo': '1 kilo',
  };

  /// Containers and portions: "X de Y" is "X of Y".
  static const Map<String, String> _measures = {
    'orden': 'order',
    'pieza': 'piece',
    'rebanada': 'slice',
    'porcion': 'portion',
    'racion': 'portion',
    'docena': 'dozen',
    'media docena': 'half dozen',
    'caja': 'box|boxes',
    'bolsa': 'bag',
    'vaso': 'glass|glasses',
    'copa': 'glass|glasses',
    'taza': 'cup',
    'jarra': 'jug',
    'tarro': 'mug',
    'botella': 'bottle',
    'lata': 'can',
    'caballito': 'shot',
    'shot': 'shot',
    'cubeta': 'bucket',
  };

  /// Measures that only hold a drink: "copa de helado" is not a glass.
  static const Set<String> _drinkContainers = {
    'vaso', 'copa', 'taza', 'jarra', 'tarro', 'botella', 'lata', //
    'caballito', 'shot', 'cubeta',
  };

  /// Packaging, service and charges: real lines, but not food or drink.
  static const Map<String, String> _service = {
    'vaso desechable': 'disposable cup',
    'vaso para llevar': 'to-go cup',
    'tapa': 'lid',
    'popote': 'straw',
    'pitillo': 'straw',
    'pajilla': 'straw',
    'servilleta': 'napkin',
    'cubiertos': 'cutlery',
    'charola': 'tray',
    'envase': 'container',
    'contenedor': 'container',
    'empaque': 'packaging',
    'deposito': 'deposit',
    'descuento': 'discount',
    'promocion': 'promotion',
    'promo': 'promotion',
    'propina': 'tip',
    'servicio': 'service',
    'servicio a domicilio': 'home delivery',
    'envio': 'delivery',
    'refill': 'refill',
    'barra libre': 'open bar',
  };

  /// Openers of an option line.
  static const Map<String, String> _leads = {
    'cambio': 'change to',
    'cambio a': 'change to',
    'cambio por': 'change to',
    'cambio de': 'change of',
    'agregar': 'add',
    'agrega': 'add',
    'quitar': 'remove',
  };

  /// What a word means when it is the whole line: a flavour ordered on its
  /// own is the drink ("JAMAICA"), and "TINTO" alone is Colombia's black
  /// coffee (next to "vino" or "copa" it is red wine, see [_drinks]).
  static const Map<String, (String, ItemKind)> _alone = {
    'tinto': ('black coffee (tinto)', ItemKind.drink),
    'jamaica': ('hibiscus drink', ItemKind.drink),
    'rosa de jamaica': ('hibiscus drink', ItemKind.drink),
    'avena': ('oatmeal', ItemKind.food),
    'elote': ('corn on the cob', ItemKind.food),
  };

  /// Names whose word-for-word English would be wrong and that have no
  /// settled English either ("pan de elote" is a moist cake, not corn
  /// bread; "pan francés" is French toast in Mexico and a bread roll in
  /// Guatemala). The dictionary stays silent and the user decides.
  static const Set<String> _noSettledEnglish = {
    'pan de elote', 'pan elote', 'torta de elote', 'pan frances', //
    'pan de nata', 'pan de pulque',
  };

  /// Heads whose meaning changes with what follows "de" ("crema de elote"
  /// is a soup, "crema de whisky" a liqueur, "crema de cacahuate" peanut
  /// butter): only the listed phrases are translated.
  static const Set<String> _onlyListedWithDe = {'crema'};

  /// Flavours that make a "torta" a cake; otherwise it is Mexico's
  /// sandwich.
  static const Set<String> _sweetFlavours = {
    'chocolate', 'vainilla', 'fresa', 'zanahoria', 'pina', 'tres leches', //
    'nuez', 'limon', 'coco', 'manzana', 'durazno', 'cajeta', 'moka', 'mango',
    'naranja', 'almendra', 'caramelo', 'dulce de leche',
  };

  /// Milk types: what an "L." in front of them stands for is "leche".
  static const Set<String> _milkTypes = {
    'entera', 'entero', 'light', 'deslactosada', 'deslactosado', //
    'descremada', 'descremado', 'semidescremada', 'semidescremado',
    'almendra', 'almendras', 'soya', 'soja', 'avena', 'coco', 'vegetal',
    'evaporada', 'condensada', 'ent', 'desc',
  };

  /// Abbreviations tills print, with the full Spanish word. Used only for
  /// a word the dictionary does not know as it stands.
  static const Map<String, String> _abbreviations = {
    'ch': 'chico',
    'chi': 'chico',
    'chic': 'chico',
    'peq': 'pequeno',
    'med': 'mediano',
    'md': 'mediano',
    'mdo': 'mediano',
    'mda': 'mediana',
    'gd': 'grande',
    'gde': 'grande',
    'grd': 'grande',
    'grde': 'grande',
    'gnde': 'grande',
    'fam': 'familiar',
    'ind': 'individual',
    'indiv': 'individual',
    'reg': 'regular',
    'jr': 'junior',
    'vt': 'venti',
    'desl': 'deslactosada',
    'deslac': 'deslactosada',
    'deslact': 'deslactosada',
    'descr': 'descremada',
    'descaf': 'descafeinado',
    'nat': 'natural',
    'min': 'mineral',
    'ext': 'extra',
    'xtra': 'extra',
    'adic': 'adicional',
    'orig': 'original',
    'trad': 'tradicional',
    'clas': 'clasico',
    'senc': 'sencillo',
    'dbl': 'doble',
    'dob': 'doble',
    'ord': 'orden',
    'paq': 'paquete',
    'pqt': 'paquete',
    'pqte': 'paquete',
    'pz': 'pieza',
    'pza': 'pieza',
    'pzas': 'piezas',
    'pzs': 'piezas',
    'reb': 'rebanada',
    'bot': 'botella',
    'lta': 'lata',
    'vso': 'vaso',
    'tza': 'taza',
    'ref': 'refresco',
    'refr': 'refresco',
    'hamb': 'hamburguesa',
    'hbg': 'hamburguesa',
    'ens': 'ensalada',
    'cerv': 'cerveza',
    'cza': 'cerveza',
    'qso': 'queso',
    'jgo': 'jugo',
    'nja': 'naranja',
    'choc': 'chocolate',
    'choco': 'chocolate',
    'vain': 'vainilla',
    'fres': 'fresa',
    'caf': 'cafe',
    'capu': 'capuchino',
    'amer': 'americano',
    'frap': 'frappe',
    'malt': 'malteada',
    'sand': 'sandwich',
    'sandw': 'sandwich',
    'sdw': 'sandwich',
    'hvo': 'huevo',
    'hvos': 'huevos',
    'poll': 'pollo',
    'pech': 'pechuga',
    'frij': 'frijoles',
    'guac': 'guacamole',
    'salch': 'salchicha',
    'jam': 'jamon',
    'toc': 'tocino',
    'champ': 'champinon',
    'pepp': 'pepperoni',
    'haw': 'hawaiana',
    'mex': 'mexicana',
    'desay': 'desayuno',
    'beb': 'bebida',
    'desech': 'desechable',
    'pesc': 'pescado',
    'bist': 'bistec',
    'bco': 'blanco',
    'llev': 'llevar',
    'mich': 'michelada',
    'teq': 'tequila',
    'ingr': 'ingrediente',
    'ing': 'ingrediente',
    'dscto': 'descuento',
    'descto': 'descuento',
    'dcto': 'descuento',
    'dto': 'descuento',
    'manz': 'manzana',
    'mzna': 'manzana',
    'duraz': 'durazno',
    'guay': 'guayaba',
    'toron': 'toronja',
    'zarz': 'zarzamora',
    'framb': 'frambuesa',
    'zan': 'zanahoria',
    'azuc': 'azucar',
  };

  /// Small words that join names.
  static const Map<String, String> _connectors = {
    'con': 'con',
    'with': 'con',
    'sin': 'sin',
    'without': 'sin',
    'y': 'y',
    'e': 'y',
    'and': 'y',
    'o': 'o',
    'u': 'o',
    'ni': 'o',
    'de': 'de',
    'del': 'de',
    'en': 'en',
    'para': 'para',
  };

  static const Map<String, String> _connectorEnglish = {
    'con': 'with',
    'sin': 'without',
    'y': 'and',
    'o': 'or',
    'en': 'in',
    'para': 'for',
  };

  /// Words of a name that are never made plural.
  static const Set<String> _smallWords = {
    'de', 'del', 'la', 'las', 'el', 'los', 'al', 'a', 'con', 'sin', 'en', //
    'y', 'para', 'por', 'no',
  };

  // ------------------------------------------------------------- the index

  static final Map<String, _Hit> _index = {};
  static final Set<String> _vocabulary = {};
  static final List<String> _conflicts = [];
  static int _written = 0;
  static int _maxWords = 1;
  static bool _built = false;

  static const _Entry _iced =
      _Entry('helado', 'iced', null, _Role.adjective, ItemKind.other);
  static const _Entry _half =
      _Entry('medio', 'half', null, _Role.adjective, ItemKind.other);
  static const _Entry _medium =
      _Entry('medio', 'medium', null, _Role.size, ItemKind.other);

  static void _build() {
    if (_built) return;
    _built = true;
    final tables = <(Map<String, String>, _Role, ItemKind, bool)>[
      (_drinks, _Role.head, ItemKind.drink, false),
      (_drinksKept, _Role.head, ItemKind.drink, false),
      (_drinksAsPrinted, _Role.head, ItemKind.drink, true),
      (_dishes, _Role.head, ItemKind.food, false),
      (_dishesKept, _Role.head, ItemKind.food, false),
      (_dishesAsPrinted, _Role.head, ItemKind.food, true),
      (_ingredients, _Role.ingredient, ItemKind.food, false),
      (_ingredientsOther, _Role.ingredient, ItemKind.other, false),
      (_ingredientsAsPrinted, _Role.ingredient, ItemKind.food, true),
      (_drinkBrands, _Role.brand, ItemKind.drink, true),
      (_foodBrands, _Role.brand, ItemKind.food, true),
      (_adjectives, _Role.adjective, ItemKind.other, false),
      (_adjectivesAsPrinted, _Role.adjective, ItemKind.other, true),
      (_after, _Role.after, ItemKind.other, false),
      (_sizes, _Role.size, ItemKind.other, false),
      (_measures, _Role.measure, ItemKind.other, false),
      (_service, _Role.head, ItemKind.other, false),
      (_leads, _Role.lead, ItemKind.other, false),
    ];
    final entries = <_Entry>[];
    // What was written down comes first and always wins over what a rule
    // makes of another entry.
    for (final (table, role, kind, asPrinted) in tables) {
      table.forEach((key, value) {
        final bar = value.indexOf('|');
        final entry = _Entry(
          key,
          bar < 0 ? value : value.substring(0, bar),
          bar < 0 ? null : value.substring(bar + 1),
          role,
          kind,
          asPrinted: asPrinted,
        );
        _written++;
        final taken = _index[key];
        if (taken != null) {
          // The same wording in two tables: one word that is both an
          // adjective and a noun ("vegetal") keeps the first.
          if (!taken.entry.sameMeaning(entry) &&
              !_bothWays.contains(key)) {
            _conflicts.add('"$key": "${taken.entry.english}" and '
                '"${entry.english}"');
          }
          return;
        }
        _index[key] = _Hit(entry, false, false);
        entries.add(entry);
      });
    }
    for (final entry in entries) {
      for (final (key, plural) in _variantsOf(entry)) {
        final taken = _index[key];
        if (taken == null) {
          _index[key] = _Hit(entry, plural, true);
        } else if (taken.derived && !taken.entry.sameMeaning(entry)) {
          _conflicts.add('"$key" (from "${taken.entry.key}" and '
              '"${entry.key}"): "${taken.entry.english}" and '
              '"${entry.english}"');
        }
      }
    }
    for (final key in _index.keys) {
      final words = key.split(' ');
      if (words.length > _maxWords) _maxWords = words.length;
      _vocabulary.addAll(words);
    }
    for (final key in _alone.keys) {
      _vocabulary.addAll(key.split(' '));
    }
  }

  /// Words written in two tables on purpose: as a describing word and as
  /// a thing.
  static const Set<String> _bothWays = {'vegetal', 'batido', 'cortado'};

  /// The other ways tills print [entry]: plural ("tacos"), feminine
  /// ("frita"), and with "de" left out ("JUGO NARANJA").
  static Iterable<(String, bool)> _variantsOf(_Entry entry) sync* {
    final words = entry.key.split(' ');
    final forms = <(List<String>, bool)>[(words, false)];
    final gendered =
        entry.role == _Role.adjective || entry.role == _Role.size;
    if (gendered && words.length == 1 && words.first.endsWith('o')) {
      final w = words.first;
      forms.add((['${w.substring(0, w.length - 1)}a'], false));
    }
    final inflects = entry.role != _Role.brand &&
        entry.role != _Role.after &&
        entry.role != _Role.lead;
    if (inflects) {
      for (final (base, _) in [...forms]) {
        for (final ending in const ['es', 's']) {
          final first = _pluralWord(base.first, ending);
          if (first == null) continue;
          forms.add(([first, ...base.skip(1)], true));
          if (base.length > 1) {
            forms.add((
              [
                for (final w in base)
                  _smallWords.contains(w) ? w : (_pluralWord(w, ending) ?? w),
              ],
              true,
            ));
          }
        }
      }
    }
    for (final (form, plural) in forms) {
      final key = form.join(' ');
      if (key != entry.key) yield (key, plural);
      // "JUGO NARANJA", "AGUA JAMAICA": the till drops the "de".
      if (form.length > 2 && form.first != 'de') {
        final short = [
          for (var i = 0; i < form.length; i++)
            if (!(i > 0 &&
                    i < form.length - 1 &&
                    (form[i] == 'de' || form[i] == 'del')) &&
                !(i > 1 &&
                    i < form.length - 1 &&
                    form[i - 1] == 'de' &&
                    (form[i] == 'la' || form[i] == 'las' || form[i] == 'los')))
              form[i],
        ];
        if (short.length != form.length) yield (short.join(' '), plural);
      }
    }
  }

  /// Spanish plural of [word]: "taco" -> "tacos", "limon" -> "limones",
  /// "nuez" -> "nueces"; borrowed words take a bare "s" ("bagels").
  static String? _pluralWord(String word, String ending) {
    if (word.length < 2 || word.endsWith('s')) return null;
    if (RegExp(r'^\d').hasMatch(word)) return null;
    final vowel = RegExp(r'[aeiou]$').hasMatch(word);
    if (ending == 's') return '${word}s';
    if (vowel) return null;
    if (word.endsWith('z')) return '${word.substring(0, word.length - 1)}ces';
    return '${word}es';
  }

  static String _pluralOf(_Entry entry) {
    if (entry.plural != null) return entry.plural!;
    final text = entry.english;
    final cut = text.indexOf(' (');
    final base = cut < 0 ? text : text.substring(0, cut);
    final rest = cut < 0 ? '' : text.substring(cut);
    if (base.endsWith('s')) return text;
    if (RegExp(r'(x|ch|sh)$').hasMatch(base)) return '${base}es$rest';
    if (RegExp(r'[^aeiou]y$').hasMatch(base)) {
      return '${base.substring(0, base.length - 1)}ies$rest';
    }
    return '${base}s$rest';
  }

  // ---------------------------------------------------------------- public

  /// The English for an item line, or null unless every word of it is
  /// understood: "MALTEADA C CHOCOLATE CH" -> "Milkshake with chocolate,
  /// small"; "MALTEADA DOÑA TOTA" -> null.
  static String? translate(String text, String language) {
    if (language != 'es') return null;
    final units = _read(text);
    if (units == null) return null;
    return _assemble(units);
  }

  /// Drink, food or neither, from the thing the line names ("PASTEL DE
  /// CAFE" is a cake, "VASO DE AGUA" a drink). Null when the dictionary
  /// cannot tell.
  static ItemKind? kindOf(String text, [String language = 'es']) {
    if (language != 'es') return null;
    final units = _read(text);
    if (units == null) return null;
    return _kindOf(units);
  }

  /// Whether the line is a choice or an extra for the item above it
  /// ("VASO DESECHABLE", "CAMBIO L. LIGHT", "EXTRA QUESO", "SIN HIELO").
  static bool isOption(String text, [String language = 'es']) {
    if (language != 'es') return false;
    final units = _read(text);
    if (units == null || units.any((u) => u.type == _U.unknown)) return false;
    final first = units.firstWhere((u) => !u.isNumber, orElse: () => units[0]);
    if (first.role == _Role.lead || first.type == _U.connector) return true;
    if (first.entry?.key == 'extra' || first.entry?.key == 'adicional') {
      return true;
    }
    return _kindOf(units) == ItemKind.other;
  }

  /// The line with till abbreviations written out and split or misread
  /// words repaired, for the translation model: "MALTEADA C CHOCOLATE CH
  /// DOÑA TOTA" -> "MALTEADA con CHOCOLATE chico DOÑA TOTA". Unchanged
  /// when there is nothing to write out.
  static String expand(String text, String language) {
    if (language != 'es') return text;
    final tokens = _repaired(text);
    if (!tokens.any((t) => t.changed)) return text;
    return [for (final t in tokens) t.changed ? t.text : t.raw].join(' ');
  }

  /// How many entries were written down (not counting plurals and other
  /// forms made by rule).
  static int get entryCount {
    _build();
    return _written;
  }

  /// Wording that was given two different meanings by accident; must be
  /// empty.
  static List<String> get conflicts {
    _build();
    return List.unmodifiable(_conflicts);
  }

  // --------------------------------------------------------------- reading

  static const String _latin1 = 'AAAAAAACEEEEIIII' 'DNOOOOOxOUUUUYTs' //
      'aaaaaaaceeeeiiii' 'dnooooo/ouuuuyty';
  static const String _latinExtendedA =
      'AaAaAaCcCcCcCcDd' 'DdEeEeEeEeEeGgGg' 'GgGgHhHhIiIiIiIi' //
      'IiIiJjKkkLlLlLlL' 'lLlNnNnNnnNnOoOo' 'OoOoRrRrRrSsSsSs'
      'SsTtTtTtUuUuUuUu' 'UuUuWwYyYZzZzZzs';

  /// Lower-case, accents and stray marks dropped ("Grandę" -> "grande"),
  /// one character out for each one in.
  static String _fold(String text) {
    final out = StringBuffer();
    for (final unit in text.codeUnits) {
      var c = unit;
      if (c >= 0xC0 && c <= 0xFF) {
        c = _latin1.codeUnitAt(c - 0xC0);
      } else if (c >= 0x100 && c <= 0x17F) {
        c = _latinExtendedA.codeUnitAt(c - 0x100);
      }
      if (c >= 0x41 && c <= 0x5A) c += 0x20;
      out.writeCharCode(c);
    }
    return out.toString();
  }

  static const String _units =
      r'mls?|lts?|ltr|litros?|l|grs?|gramos|g|kgs?|kilos?|oz|onzas?|'
      r'pzas?|pzs?|piezas?|cc|cl|pack|pk|min|hrs?';

  static final RegExp _scanner = RegExp(
    // "M&M"
    r"(?<mm>(?<![a-z0-9])m\s?&\s?m'?s?(?![a-z0-9]))"
    // "C/QUESO", "S/HIELO", "P/LLEVAR"
    r'|(?<prep>(?<![a-z0-9])[csp])\s?/\s?(?=[a-z])'
    // "2x1"
    r'|(?<promo>(?<![a-z0-9])\d+\s?x\s?\d+(?![a-z0-9]))'
    // "887 ML", "20GR", "1/2 L", "1.5LT"
    r'|(?<![a-z0-9/.,])(?<qty>\d+/\d+|\d+(?:[.,]\d+)?)\s*'
    '(?<unit>$_units)'
    r'(?![a-z0-9])'
    r'|(?<word>[a-z0-9]*[a-z][a-z0-9]*)'
    r'|(?<frac>\d+/\d+)'
    r'|(?<num>#?\d+(?:[.,]\d+)*%?)'
    r'|(?<and>[&+])'
    r'|(?<slash>/)',
  );

  static const Map<String, String> _unitEnglish = {
    'ml': 'ml', 'mls': 'ml', 'cc': 'cc', 'cl': 'cl', //
    'l': 'L', 'lt': 'L', 'lts': 'L', 'ltr': 'L', 'litro': 'L', 'litros': 'L',
    'g': 'g', 'gr': 'g', 'grs': 'g', 'gramos': 'g',
    'kg': 'kg', 'kgs': 'kg', 'kilo': 'kg', 'kilos': 'kg',
    'oz': 'oz', 'onza': 'oz', 'onzas': 'oz',
    'min': 'min', 'hr': 'h', 'hrs': 'h',
  };

  /// The line as tokens: words, numbers and quantities ("20GR" -> "20 g").
  static List<_Token> _scan(String text) {
    final clean = text.replaceAll(RegExp('[̀-ͯ’\']'), '');
    final folded = _fold(clean);
    final tokens = <_Token>[];
    for (final m in _scanner.allMatches(folded)) {
      final raw = clean.substring(m.start, m.end).trim();
      if (m.namedGroup('mm') != null) {
        tokens.add(_Token(_T.word, 'mms', raw));
      } else if (m.namedGroup('prep') != null) {
        final word = const {'c': 'con', 's': 'sin', 'p': 'para'}[
            m.namedGroup('prep')]!;
        tokens.add(_Token(_T.word, word, raw, changed: true));
      } else if (m.namedGroup('promo') != null) {
        tokens.add(_Token(
            _T.number, m.namedGroup('promo')!.replaceAll(' ', ''), raw));
      } else if (m.namedGroup('qty') != null) {
        final number = m.namedGroup('qty')!.replaceAll(',', '.');
        final unit = m.namedGroup('unit')!;
        final String english;
        if (unit.startsWith('p') && unit != 'pack' && unit != 'pk') {
          english = number == '1' ? '1 piece' : '$number pieces';
        } else if (unit == 'pack' || unit == 'pk') {
          english = '$number-pack';
        } else {
          english = '$number ${_unitEnglish[unit]}';
        }
        tokens.add(_Token(_T.quantity, english, raw));
      } else if (m.namedGroup('word') != null) {
        tokens.add(_Token(_T.word, m.namedGroup('word')!, raw));
      } else if (m.namedGroup('frac') != null) {
        tokens.add(_Token(_T.number, m.namedGroup('frac')!, raw));
      } else if (m.namedGroup('num') != null) {
        tokens.add(_Token(_T.number, m.namedGroup('num')!, raw));
      } else if (m.namedGroup('and') != null) {
        tokens.add(_Token(_T.word, 'y', raw));
      } else {
        tokens.add(_Token(_T.slash, '/', raw));
      }
    }
    return tokens;
  }

  static bool _isLetter(String word) =>
      word.length == 1 && RegExp('[a-z]').hasMatch(word);

  /// A word the rules can work with as it stands.
  static bool _known(String word) =>
      _vocabulary.contains(word) ||
      _connectors.containsKey(word) ||
      _abbreviations.containsKey(word) ||
      word == 'medio' ||
      word == 'media';

  /// [_scan], then every repair: split and glued words, abbreviations,
  /// and letters misread.
  static List<_Token> _repaired(String text) {
    _build();
    final tokens = _scan(text);
    _splitDigits(tokens);
    _rejoin(tokens);
    _unglue(tokens);
    _writeOut(tokens);
    _respell(tokens);
    return tokens;
  }

  /// "C0CA" -> "coca", "5PRITE" -> "sprite": a digit read for the letter
  /// it looks like, inside a word. Anything else with digits is a word
  /// and a number printed together ("COMBO1" -> "combo 1").
  static void _splitDigits(List<_Token> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.type != _T.word || !RegExp(r'\d').hasMatch(t.text)) continue;
      if (_vocabulary.contains(t.text)) continue;
      String? repaired;
      for (final one in const ['i', 'l']) {
        final candidate = t.text
            .replaceAll('0', 'o')
            .replaceAll('1', one)
            .replaceAll('5', 's')
            .replaceAll('8', 'b');
        if (!RegExp(r'\d').hasMatch(candidate) &&
            _vocabulary.contains(candidate)) {
          repaired = candidate;
          break;
        }
      }
      if (repaired != null) {
        t
          ..text = repaired
          ..changed = true;
        continue;
      }
      final pieces = RegExp(r'[a-z]+|\d+')
          .allMatches(t.text)
          .map((m) => m.group(0)!)
          .toList();
      tokens.removeAt(i);
      for (var j = 0; j < pieces.length; j++) {
        final digits = RegExp(r'^\d').hasMatch(pieces[j]);
        tokens.insert(
          i + j,
          _Token(digits ? _T.number : _T.word, pieces[j],
              j == 0 ? t.raw : '',
              changed: false),
        );
      }
      i += pieces.length - 1;
    }
    tokens.removeWhere((t) => t.text.isEmpty);
  }

  /// "REFRE SCO" -> "refresco", "C HOCOLATE" -> "chocolate": pieces of
  /// one word the printer's gap split, when at least one piece means
  /// nothing alone and together they are a word of the dictionary.
  static void _rejoin(List<_Token> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      for (final n in const [3, 2]) {
        if (i + n > tokens.length) continue;
        final pieces = tokens.sublist(i, i + n);
        if (pieces.any((t) => t.type != _T.word)) continue;
        if (pieces.every((t) => _known(t.text))) continue;
        final joined = pieces.map((t) => t.text).join();
        if (joined.length < 4 || !_vocabulary.contains(joined)) continue;
        tokens
          ..removeRange(i, i + n)
          ..insert(
            i,
            _Token(_T.word, joined, pieces.map((t) => t.raw).join(),
                changed: true),
          );
        break;
      }
    }
  }

  /// "AGUAMINERAL" -> "agua mineral", "SINHIELO" -> "sin hielo": two
  /// words printed with no gap, when the word is unknown and splits one
  /// way only.
  static void _unglue(List<_Token> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.type != _T.word || t.text.length < 6 || _known(t.text)) continue;
      (String, String)? found;
      var ways = 0;
      for (var k = 3; k <= t.text.length - 3; k++) {
        final left = t.text.substring(0, k);
        final right = t.text.substring(k);
        final leftOk = _vocabulary.contains(left) ||
            left == 'con' ||
            left == 'sin' ||
            left == 'para';
        if (leftOk && _vocabulary.contains(right)) {
          ways++;
          found = (left, right);
        }
      }
      if (ways != 1) continue;
      tokens
        ..removeAt(i)
        ..insert(i, _Token(_T.word, found!.$1, found.$1, changed: true))
        ..insert(i + 1, _Token(_T.word, found.$2, found.$2, changed: true));
      i++;
    }
  }

  /// Abbreviations written out in full, by what stands next to them:
  /// "C" between words is "con", "L." before a milk type is "leche",
  /// "DESC" after milk is "descremada" and otherwise "descuento".
  static void _writeOut(List<_Token> tokens) {
    String? wordAt(int i) =>
        i >= 0 && i < tokens.length && tokens[i].type == _T.word
            ? tokens[i].text
            : null;
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.type != _T.word || _vocabulary.contains(t.text)) continue;
      String? full;
      final next = wordAt(i + 1);
      final before = wordAt(i - 1);
      if (t.text == 'c') {
        if (next != null && !_isLetter(next)) full = 'con';
      } else if (t.text == 'l') {
        final after = next == 'de' ? wordAt(i + 2) : next;
        if (after != null && _milkTypes.contains(after)) full = 'leche';
      } else if (t.text == 'desc') {
        full = before == 'leche' || before == 'yogurt'
            ? 'descremada'
            : 'descuento';
      } else if (t.text == 'ent') {
        if (before == 'leche') full = 'entera';
      } else {
        full = _abbreviations[t.text];
      }
      if (full != null) {
        t
          ..text = full
          ..changed = true;
      }
    }
  }

  /// Read errors in a word the dictionary does not know, tried in turn;
  /// each repair is taken only when it leads to exactly one known word.
  static void _respell(List<_Token> tokens) {
    for (final t in tokens) {
      if (t.type != _T.word || _isLetter(t.text) || _known(t.text)) continue;
      final repaired = _lookalike(t.text) ?? _completed(t.text);
      if (repaired != null) {
        t
          ..text = repaired
          ..changed = true;
      }
    }
  }

  /// "LEOHE" -> "leche", "CHIIE" -> "chile", "WVHIP" -> "whip", "CAME"
  /// -> "carne": letters OCR confuses (c with o or e, i with l, "rn"
  /// with "m", w with "vv"), in a word of five letters or more.
  static String? _lookalike(String word) {
    if (word.length < 4) return null;
    final candidates = <String>{};
    void consider(String candidate) {
      if (candidate != word && _index.containsKey(candidate)) {
        candidates.add(candidate);
      }
    }

    for (final (from, to) in const [
      ('wv', 'w'), ('vv', 'w'), ('rn', 'm'), ('m', 'rn'), //
    ]) {
      var at = word.indexOf(from);
      while (at >= 0) {
        consider(word.replaceRange(at, at + from.length, to));
        at = word.indexOf(from, at + 1);
      }
    }
    if (word.length >= 5) {
      const swaps = {
        'c': ['o', 'e'],
        'o': ['c'],
        'e': ['c'],
        'i': ['l'],
        'l': ['i'],
      };
      for (var i = 0; i < word.length; i++) {
        for (final to in swaps[word[i]] ?? const <String>[]) {
          consider(word.replaceRange(i, i + 1, to));
        }
      }
      // Every i and l at once: "POIIO" -> "pollo".
      consider(word.replaceAll('i', 'l'));
    }
    return _oneMeaning(candidates);
  }

  /// "HAMBURG" -> "hamburguesa", "DESLACTOS" -> "deslactosada": a word
  /// the column cut short, six letters or more, that only one word of
  /// the dictionary starts with.
  static String? _completed(String word) {
    if (word.length < 6) return null;
    final candidates = <String>{};
    var inPhraseOnly = false;
    for (final known in _vocabulary) {
      if (known.length > word.length && known.startsWith(word)) {
        if (_index.containsKey(known)) {
          candidates.add(known);
        } else {
          inPhraseOnly = true;
        }
      }
    }
    return inPhraseOnly ? null : _oneMeaning(candidates);
  }

  /// The shortest of [words] when they are all forms of one entry.
  static String? _oneMeaning(Set<String> words) {
    if (words.isEmpty) return null;
    final first = _index[words.first]!.entry;
    if (words.any((w) => !_index[w]!.entry.sameMeaning(first))) return null;
    return words.reduce((a, b) => a.length <= b.length ? a : b);
  }

  /// The line as dictionary units, or null when it holds no word at all.
  static List<_Unit>? _read(String text) {
    final tokens = _repaired(text);
    if (!tokens.any((t) => t.type == _T.word)) return null;
    final spoken = [
      for (final t in tokens)
        if (t.type == _T.word || t.type == _T.number) t.text,
    ].join(' ');
    if (_noSettledEnglish.contains(spoken)) {
      return [_Unit(_U.unknown, spoken)];
    }
    final units = <_Unit>[];
    var i = 0;
    while (i < tokens.length) {
      final t = tokens[i];
      // The longest name that starts here.
      var matched = 0;
      for (var n = _maxWords; n >= 1 && matched == 0; n--) {
        if (i + n > tokens.length) continue;
        final window = tokens.sublist(i, i + n);
        if (window.any((w) => w.type != _T.word && w.type != _T.number)) {
          continue;
        }
        if (n == 1 && t.type == _T.number) continue;
        final hit = _index[window.map((w) => w.text).join(' ')];
        if (hit == null) continue;
        units.add(_Unit(_U.entry, '', entry: hit.entry, plural: hit.plural));
        matched = n;
      }
      if (matched > 0) {
        i += matched;
        continue;
      }
      i++;
      if (t.type == _T.number) {
        units.add(_Unit(_U.number, t.text));
      } else if (t.type == _T.quantity) {
        units.add(_Unit(_U.quantity, t.text));
      } else if (t.type == _T.slash) {
        units.add(_Unit(_U.connector, '/'));
      } else if (_connectors.containsKey(t.text)) {
        units.add(_Unit(_U.connector, _connectors[t.text]!));
      } else if (t.text == 'medio' || t.text == 'media') {
        // "MEDIA ORDEN" is half an order; "LATTE MEDIA" a medium latte.
        final next = i < tokens.length ? _index[tokens[i].text] : null;
        final half = next != null &&
            (next.entry.role == _Role.head ||
                next.entry.role == _Role.measure ||
                next.entry.role == _Role.ingredient);
        units.add(_Unit(_U.entry, '', entry: half ? _half : _medium)
          ..needsDrink = !half);
      } else if (_isLetter(t.text)) {
        units.add(_Unit(_U.letter, t.text.toUpperCase()));
      } else {
        units.add(_Unit(_U.unknown, t.text));
      }
    }
    _inContext(units);
    return units;
  }

  /// Meanings that depend on the rest of the line.
  static void _inContext(List<_Unit> units) {
    // "TE HELADO" is iced tea; "HELADO" on its own or first is ice cream.
    var drinkBefore = false;
    for (final u in units) {
      if (u.entry?.key == 'helado' && drinkBefore) u.entry = _iced;
      if (u.role == _Role.head && u.entry!.kind == ItemKind.drink) {
        drinkBefore = true;
      }
      if (u.type == _U.connector && u.text != 'de') drinkBefore = false;
    }
    // A word that is the whole line.
    final core = [
      for (final u in units)
        if (!u.isNumber && u.role != _Role.size) u,
    ];
    if (core.length == 1) {
      final only = core.single;
      final key = only.entry?.key ?? only.text;
      final alone = _alone[key];
      if (alone != null) {
        final at = units.indexOf(only);
        units[at] = _Unit(
          _U.entry,
          '',
          entry: _Entry(key, alone.$1, null, _Role.head, alone.$2),
        );
      }
    }
  }

  static ItemKind? _kindOf(List<_Unit> units) {
    final understood = units.every((u) => u.type != _U.unknown);
    for (final role in const [_Role.head, _Role.brand, _Role.ingredient]) {
      for (final u in units) {
        if (u.type == _U.unknown) break;
        if (u.role == role) return u.entry!.kind;
      }
      if (units.any((u) => u.role == role)) return null;
    }
    return understood ? ItemKind.other : null;
  }

  // ------------------------------------------------------------- assembling

  static String? _assemble(List<_Unit> all) {
    if (all.any((u) => u.type == _U.unknown)) return null;
    if (!all.any((u) => u.type == _U.entry)) return null;
    // A lone letter is a till's own code ("Caramel Iced Whip L"): kept as
    // printed, but only one, and never to open the line.
    final letters = all.where((u) => u.type == _U.letter).length;
    if (letters > 1 || (letters == 1 && all.first.type == _U.letter)) {
      return null;
    }
    final sizes = <String>[];
    final rest = <_Unit>[];
    for (final u in all) {
      if (u.role == _Role.size) {
        if (u.needsDrink && _kindOf(all) != ItemKind.drink) return null;
        sizes.add(u.english);
      } else {
        rest.add(u);
      }
    }
    final out = <String>[];
    if (rest.isNotEmpty && rest.first.role == _Role.lead) {
      out.add(rest.removeAt(0).english);
      if (rest.isEmpty || rest.first.type == _U.connector) return null;
    }
    if (rest.any((u) => u.role == _Role.lead)) return null;

    // Names joined by "con", "sin", "y"...; "de" stays inside a name.
    var name = <_Unit>[];
    String? joiner;
    var first = true;
    bool close() {
      if (name.isEmpty) return first && joiner == null;
      final english = _name(name);
      if (english == null) return false;
      if (joiner == '/') {
        out[out.length - 1] = '${out.last}/$english';
      } else {
        if (joiner != null) out.add(_connectorEnglish[joiner]!);
        out.add(english);
      }
      return true;
    }

    for (var i = 0; i < rest.length; i++) {
      final u = rest[i];
      if (u.type != _U.connector) {
        name.add(u);
        continue;
      }
      final next = i + 1 < rest.length ? rest[i + 1] : null;
      if (next == null || next.type == _U.connector) return null;
      if (u.text == 'de') {
        if (name.isEmpty) return null;
        next.linked = true;
        continue;
      }
      // "SANDWICH DE JAMON Y QUESO": the "y" joins two fillings of one
      // sandwich, not a sandwich and a cheese.
      if (u.text == 'y' &&
          name.length > 1 &&
          (name.last.role == _Role.ingredient ||
              name.last.role == _Role.brand) &&
          name.any((n) => n.role == _Role.head) &&
          next.role == _Role.ingredient) {
        next.joined = true;
        continue;
      }
      if (u.text == '/' && name.isEmpty) return null;
      if (!close()) return null;
      if (name.isEmpty && !first) return null;
      first = false;
      name = <_Unit>[];
      joiner = u.text;
      if (joiner == '/' && out.isEmpty) return null;
    }
    if (name.isEmpty && joiner != null) return null;
    if (!close()) return null;

    var text = out.join(' ');
    if (sizes.isNotEmpty) {
      text = text.isEmpty ? sizes.join(', ') : '$text, ${sizes.join(', ')}';
    }
    if (text.isEmpty) return null;
    return text[0].toUpperCase() + text.substring(1);
  }

  /// One name in English word order: what describes goes in front of the
  /// thing ("leche entera" -> "whole milk", "jugo de naranja" -> "orange
  /// juice"), numbers keep their place at the start or the end.
  static String? _name(List<_Unit> units) {
    var start = 0;
    final leading = <String>[];
    while (start < units.length && units[start].isNumber) {
      leading.add(units[start].text);
      start++;
    }
    final body = units.sublist(start);
    if (body.isEmpty) return leading.join(' ');
    final String? english;
    final lead = body.indexWhere((u) => u.role != _Role.adjective);
    if (lead >= 0 && body[lead].role == _Role.measure) {
      english = _measured(body, lead);
    } else {
      english = _described(body);
    }
    if (english == null) return null;
    if (leading.isEmpty) return english;
    // "2 PZAS POLLO" -> "2 pieces of chicken".
    final of = leading.last.endsWith('piece') || leading.last.endsWith('pieces')
        ? ' of'
        : '';
    return '${leading.join(' ')}$of $english';
  }

  /// "ORDEN DE PAPAS" -> "order of fries", "MEDIA ORDEN" -> "half order".
  static String? _measured(List<_Unit> body, int at) {
    final measure = body[at];
    final own = <String>[for (final u in body.take(at)) u.singular];
    var k = at + 1;
    final behind = <String>[];
    while (k < body.length &&
        body[k].role == _Role.adjective &&
        !body[k].linked) {
      behind.insert(0, body[k].singular);
      k++;
    }
    final words = [...behind, ...own, measure.english].join(' ');
    final inside = body.sublist(k);
    if (inside.isEmpty) return words;
    if (inside.every((u) => u.isNumber)) {
      return '$words ${inside.map((u) => u.text).join(' ')}';
    }
    if (_drinkContainers.contains(measure.entry!.key) &&
        _kindOf(inside) != ItemKind.drink) {
      return null;
    }
    inside.first.linked = false;
    final english = _name(inside);
    return english == null ? null : '$words of $english';
  }

  static String? _described(List<_Unit> body) {
    // Numbers: "COMBO 1" keeps its number behind; a quantity in the
    // middle ("AGUA 600ML CIEL") moves behind; a bare number in the
    // middle ("TACOS 3 QUESOS") belongs to what follows, which the
    // dictionary does not guess.
    final words = <_Unit>[];
    final numbers = <String>[];
    for (var i = 0; i < body.length; i++) {
      final u = body[i];
      if (!u.isNumber) {
        words.add(u);
        continue;
      }
      final last = body.skip(i + 1).every((x) => x.isNumber);
      if (u.type == _U.number && !last) return null;
      if (i + 1 < body.length) body[i + 1].linked = false;
      numbers.add(u.text);
    }
    if (words.isEmpty) return null;

    var h = words.indexWhere((u) => u.role == _Role.head);
    if (h < 0) h = words.indexWhere((u) => u.role == _Role.brand);
    if (h < 0) h = words.indexWhere((u) => u.role == _Role.ingredient);
    if (h < 0) {
      // Only describing words: "MINERAL", "PARA LLEVAR", "DESLACTOSADA".
      if (words.any((u) => u.role == _Role.measure)) return null;
      return [...words.map((u) => u.singular), ...numbers].join(' ');
    }
    final head = words[h];
    final front = <String>[];
    for (final u in words.take(h)) {
      // In front of the thing as printed ("NUTELLA LATTE", "EXTRA
      // QUESO"): only words that can stand there.
      if (u.linked || !(u.role == _Role.adjective || u.isNoun)) return null;
      front.add(u.singular);
    }
    if (head.linked && words.take(h).any((u) => u.isNoun)) return null;

    // "LATTE FRAPPE", "CLUB SANDWICH": English names keep their order.
    var end = h + 1;
    if (head.role == _Role.head && head.entry!.asPrinted) {
      while (end < words.length &&
          words[end].role == _Role.head &&
          words[end].entry!.asPrinted &&
          !words[end].linked &&
          !words[end].joined) {
        end++;
      }
    }
    final describing = <String>[];
    final groups = <List<_Unit>>[];
    final behind = <String>[];
    final packs = <String>[];
    var nounBefore = false;
    for (var i = end; i < words.length; i++) {
      final u = words[i];
      switch (u.role) {
        case _Role.adjective:
          describing.insert(0, u.singular);
          nounBefore = false;
        case _Role.after:
        case null:
          behind.add(u.singular);
          nounBefore = false;
        case _Role.measure:
          // "COCA ZERO BOT": how it comes, after a comma.
          if (u.linked) return null;
          if (i + 1 < words.length && words[i + 1].linked) return null;
          packs.add(u.singular);
          nounBefore = false;
        case _Role.head:
        case _Role.ingredient:
        case _Role.brand:
          if (head.role == _Role.brand) {
            // "FANTA NARANJA": a brand's flavour follows it.
            behind.add(u.singular);
            break;
          }
          // A second dish further along ("TE VERDE LATTE") is not a
          // filling of the first.
          if (u.role == _Role.head && !(i == end || u.linked)) return null;
          // "JAMON QUESO": two ingredients side by side with nothing to
          // say which describes which.
          if (head.role == _Role.ingredient &&
              u.role == _Role.ingredient &&
              !u.linked) {
            return null;
          }
          if (u.joined ||
              (nounBefore && !u.linked && u.role != _Role.head)) {
            groups.last.add(u);
          } else {
            groups.add([u]);
          }
          nounBefore = true;
        case _Role.size:
        case _Role.lead:
          return null;
      }
    }
    if (groups.isNotEmpty && _onlyListedWithDe.contains(head.entry!.key)) {
      return null;
    }

    var thing = [
      for (var i = h; i < end; i++)
        i == end - 1 ? words[i].english : words[i].singular,
    ].join(' ');
    final alone = front.isEmpty &&
        describing.isEmpty &&
        groups.isEmpty &&
        behind.isEmpty;
    if (head.entry!.key == 'papa' && head.plural && alone) {
      // At a till, "PAPAS" with nothing said about them are fries.
      thing = 'fries';
    } else if (head.entry!.key == 'torta') {
      final sweet = groups
          .expand((g) => g)
          .any((u) => _sweetFlavours.contains(u.entry!.key));
      if (sweet) thing = head.plural ? 'cakes' : 'cake';
    }
    final fillings = [
      for (final group in groups.reversed)
        group.length == 1
            ? group.single.singular
            : '${group.take(group.length - 1).map((u) => u.singular).join(', ')}'
                ' and ${group.last.singular}',
    ];
    final english = [
      ...describing,
      ...front,
      ...fillings,
      thing,
      ...behind,
      ...numbers,
    ].join(' ');
    return packs.isEmpty ? english : '$english, ${packs.join(', ')}';
  }
}
