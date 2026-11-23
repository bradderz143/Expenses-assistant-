import 'package:expense_assistant/domain/logic/item_lexicon.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every till line of [lines] must come out as the English next to it.
void expectEnglish(Map<String, String> lines) {
  lines.forEach((printed, english) {
    expect(ItemLexicon.translate(printed, 'es'), english, reason: printed);
  });
}

/// Lines the dictionary must leave to the model and the user.
void expectNotRead(List<String> lines) {
  for (final printed in lines) {
    expect(ItemLexicon.translate(printed, 'es'), isNull, reason: printed);
  }
}

void main() {
  group('the lines the translation model got wrong', () {
    test('coffee-shop ticket', () {
      expectEnglish({
        'MALTEADA C CHOCOLATE CH': 'Milkshake with chocolate, small',
        'VASO DESECHABLE': 'Disposable cup',
        'CAMBIO L. LIGHT': 'Change to light milk',
        'NUTELLA LATTE FRAPPE GD': 'Nutella latte frappe, large',
        'L. ENTERA': 'Whole milk',
        'EXTRA CREMA BATIDA 20GR': 'Extra whipped cream 20 g',
        'LIMONADA': 'Lemonade',
        'MINERAL': 'Sparkling',
        'Leche Deslactosada MD': 'Lactose-free milk, medium',
        'Chocolate Frappe Grande': 'Chocolate frappe, large',
      });
    });

    test('fast-food ticket', () {
      expectEnglish({
        'REFRESCO 887 ML': 'Soft drink 887 ml',
        'COLA 887 ML': 'Cola 887 ml',
        'PAPAS FAM': 'Fries, family size',
      });
    });

    test('a line with a word nobody could know is left alone', () {
      expectNotRead(['Desc. 10% AICM']);
    });
  });

  group('cafes', () {
    test('coffee and tea', () {
      expectEnglish({
        'CAFE AMERICANO': 'Americano',
        'CAFE AMERICANO GDE': 'Americano, large',
        'AMERICANO CH': 'Americano, small',
        'AMERICANO DESCAFEINADO': 'Decaf americano',
        'CAPUCHINO MED': 'Cappuccino, medium',
        'CAPUCHINO VAINILLA GD': 'Vanilla cappuccino, large',
        'CAPUCHINO DESLACTOSADO GDE': 'Lactose-free cappuccino, large',
        'LATTE VAINILLA CH': 'Vanilla latte, small',
        'LATTE CARAMELO': 'Caramel latte',
        'LATTE HELADO': 'Iced latte',
        'ESPRESSO DOBLE': 'Double espresso',
        'EXPRESO DOBLE': 'Double espresso',
        'CAFE DE OLLA': 'Café de olla (spiced coffee)',
        'CAFE CON LECHE': 'Coffee with milk',
        'CAFE HELADO': 'Iced coffee',
        'CHOCOLATE CALIENTE': 'Hot chocolate',
        'CHOCOLATE CALIENTE CH': 'Hot chocolate, small',
        'TE VERDE': 'Green tea',
        'TE DE MANZANILLA': 'Chamomile tea',
        'TE HELADO': 'Iced tea',
        'TE HELADO DE DURAZNO': 'Iced peach tea',
        'TE CHAI LATTE': 'Chai tea latte',
        'CHAI LATTE GD': 'Chai latte, large',
        'MATCHA LATTE': 'Matcha latte',
        'CARAMEL MACCHIATO': 'Caramel macchiato',
        'FLAT WHITE': 'Flat white',
        'TAZA DE CAFE': 'Cup of coffee',
      });
    });

    test('blended and cold drinks', () {
      expectEnglish({
        'FRAPPE MOKA': 'Mocha frappe',
        'FRAPPE OREO GDE': 'Oreo frappe, large',
        'MOKA GDE': 'Mocha, large',
        'SMOOTHIE DE FRESA': 'Strawberry smoothie',
        'MALTEADA DE FRESA': 'Strawberry milkshake',
        'MALTEADA VAINILLA GD': 'Vanilla milkshake, large',
        'MALTEADA OREO': 'Oreo milkshake',
        'LICUADO DE PLATANO': 'Banana smoothie',
        'LICUADO DE FRESA C/LECHE DESL':
            'Strawberry smoothie with lactose-free milk',
        'JUGO DE NARANJA': 'Orange juice',
        'JUGO NARANJA CH': 'Orange juice, small',
        'JUGO VERDE GDE': 'Green juice, large',
        'JUGO DE ZANAHORIA': 'Carrot juice',
        'JUGO DE TORONJA': 'Grapefruit juice',
      });
    });

    test('what goes with the drink', () {
      expectEnglish({
        'L. DESLACTOSADA': 'Lactose-free milk',
        'L. DESL': 'Lactose-free milk',
        'L. ALMENDRA': 'Almond milk',
        'LECHE DE SOYA': 'Soy milk',
        'LECHE DE AVENA': 'Oat milk',
        'LECHE DESC': 'Skimmed milk',
        'LECHE ENT': 'Whole milk',
        'CAMBIO A LECHE DE COCO': 'Change to coconut milk',
        'CAMBIO DE LECHE A DESLACTOSADA': 'Change of milk to lactose-free',
        'EXTRA SHOT': 'Extra shot',
        'SHOT ESPRESSO': 'Shot of espresso',
        'SIN AZUCAR': 'Without sugar',
        'S/HIELO': 'Without ice',
        'CON HIELO': 'With ice',
        'PARA LLEVAR': 'To go',
        'P/LLEVAR': 'To go',
        'PARA AQUI': 'To eat in',
        'TAPA': 'Lid',
        'POPOTE': 'Straw',
        'BOLSA DE PAPEL': 'Paper bag',
      });
    });

    test('pastry counter', () {
      expectEnglish({
        'CROISSANT DE JAMON Y QUESO': 'Ham and cheese croissant',
        'CUERNITO JAMON Y QUESO': 'Ham and cheese croissant',
        'BAGEL C/QUESO CREMA': 'Bagel with cream cheese',
        'PANINI DE POLLO': 'Chicken panini',
        'BAGUETTE DE PAVO': 'Turkey baguette',
        'SANDWICH DE JAMON Y QUESO': 'Ham and cheese sandwich',
        'SANDWICH DE ATUN': 'Tuna sandwich',
        'MUFFIN DE CHOCOLATE': 'Chocolate muffin',
        'GALLETA DE AVENA': 'Oat cookie',
        'GALLETA CHISPAS CHOCOLATE': 'Chocolate chip cookie',
        'DONA GLASEADA': 'Glazed doughnut',
        'DONA DE CHOCOLATE': 'Chocolate doughnut',
        'ROL DE CANELA': 'Cinnamon roll',
        'BROWNIE': 'Brownie',
        'PAN DULCE': 'Sweet bread',
        'CONCHA': 'Concha (sweet bread)',
        'PASTEL DE CHOCOLATE': 'Chocolate cake',
        'REBANADA DE PASTEL': 'Slice of cake',
        'REB PASTEL CHOCOLATE': 'Slice of chocolate cake',
        'PASTEL ZANAHORIA': 'Carrot cake',
        'PASTEL DE TRES LECHES': 'Tres leches cake',
        'PAY DE LIMON': 'Lime pie',
        'PAY DE QUESO': 'Cheesecake',
        'CHEESECAKE DE FRESA': 'Strawberry cheesecake',
        'FLAN NAPOLITANO': 'Flan napolitano',
        'CHURROS': 'Churros',
        'DOCENA DE DONAS': 'Dozen doughnuts',
      });
    });
  });

  group('water and soft drinks', () {
    test('water', () {
      expectEnglish({
        'AGUA NATURAL': 'Still water',
        'AGUA MINERAL': 'Mineral water',
        'AGUA MINERAL 600ML': 'Mineral water 600 ml',
        'AGUA EMBOTELLADA': 'Bottled water',
        'AGUA CIEL 600 ML': 'Ciel water 600 ml',
        'AGUA 600ML CIEL': 'Ciel water 600 ml',
        'AGUA BONAFONT 1.5LT': 'Bonafont water 1.5 L',
        'BOTELLA DE AGUA': 'Bottle of water',
        'VASO DE AGUA': 'Glass of water',
        'AGUA CON GAS': 'Sparkling water',
        'AGUA SIN GAS': 'Still water',
        'AGUA TONICA': 'Tonic water',
        'TOPO CHICO 355ML': 'Topo Chico 355 ml',
      });
    });

    test('aguas frescas and lemonades', () {
      expectEnglish({
        'AGUA DE JAMAICA': 'Hibiscus water',
        'AGUA JAMAICA 1 LT': 'Hibiscus water 1 L',
        'JAMAICA GDE': 'Hibiscus drink, large',
        'AGUA DE HORCHATA': 'Horchata (rice drink)',
        'HORCHATA': 'Horchata',
        'AGUA DE SABOR': 'Flavoured water',
        'JARRA DE AGUA DE JAMAICA': 'Jug of hibiscus water',
        'LIMONADA MINERAL': 'Sparkling lemonade',
        'LIMONADA NATURAL GDE': 'Still lemonade, large',
        'NARANJADA MINERAL': 'Sparkling orangeade',
      });
    });

    test('soft drinks', () {
      expectEnglish({
        'REFRESCO': 'Soft drink',
        'REFRESCO DE LATA': 'Soft drink, can',
        'REF. LATA': 'Soft drink, can',
        'REF 600ML': 'Soft drink 600 ml',
        'REFRESCO REFILL': 'Soft drink refill',
        'COCA COLA': 'Coca-Cola',
        'COCA-COLA': 'Coca-Cola',
        'COCA COLA 600ML': 'Coca-Cola 600 ml',
        'COCA COLA LIGHT': 'Coca-Cola Light',
        'COCA ZERO BOT': 'Coca-Cola Zero, bottle',
        'COCA-COLA S/AZUCAR 355ML': 'Coca-Cola Zero Sugar 355 ml',
        'COCA COLA MED': 'Coca-Cola, medium',
        'LATA COCA COLA 355ML': 'Can of Coca-Cola 355 ml',
        'SPRITE 355 ML': 'Sprite 355 ml',
        'SPRITE ZERO': 'Sprite Zero',
        'FRESCA 600ML': 'Fresca 600 ml',
        'RED BULL 250ML': 'Red Bull 250 ml',
      });
    });
  });

  group('Mexican restaurants and taquerias', () {
    test('tacos and antojitos keep their names', () {
      expectEnglish({
        'TACOS AL PASTOR': 'Tacos al pastor',
        'TACO PASTOR': 'Taco al pastor',
        'ORDEN DE TACOS AL PASTOR': 'Order of tacos al pastor',
        'ORD TACOS PASTOR': 'Order of tacos al pastor',
        'MEDIA ORDEN DE TACOS': 'Half order of tacos',
        'TACOS DE BISTEC': 'Steak tacos',
        'TACO DE SUADERO': 'Suadero taco',
        'TACOS DE ARRACHERA': 'Skirt steak tacos',
        'TACOS DE ASADA': 'Carne asada tacos',
        'TACOS DE BIRRIA': 'Birria tacos',
        'TACOS DE CANASTA': 'Tacos de canasta',
        'TACOS DORADOS': 'Crispy tacos',
        'GRINGA': 'Gringa',
        'GRINGA PASTOR': 'Gringa al pastor',
        'QUESADILLA DE QUESO': 'Cheese quesadilla',
        'QUESADILLAS DE FLOR DE CALABAZA': 'Squash blossom quesadillas',
        'SOPE DE POLLO': 'Chicken sope',
        'HUARACHE DE BISTEC': 'Steak huarache',
        'TLAYUDA': 'Tlayuda',
        'FLAUTAS DE POLLO': 'Chicken flautas',
        'BURRITO DE ASADA': 'Carne asada burrito',
        'QUESO FUNDIDO C/CHORIZO': 'Queso fundido with chorizo',
        'GUACAMOLE C/TOTOPOS': 'Guacamole with tortilla chips',
        'ORDEN DE GUACAMOLE': 'Order of guacamole',
        'ALAMBRE DE RES': 'Beef alambre',
        'TORTILLAS DE HARINA': 'Flour tortillas',
        'ORDEN EXTRA DE TORTILLAS': 'Extra order of tortillas',
      });
    });

    test('breakfast', () {
      expectEnglish({
        'CHILAQUILES VERDES': 'Green chilaquiles',
        'CHILAQUILES ROJOS C/HUEVO': 'Red chilaquiles with egg',
        'CHILAQUILES C/POLLO': 'Chilaquiles with chicken',
        'ENCHILADAS SUIZAS': 'Enchiladas suizas',
        'ENCHILADAS VERDES C/POLLO': 'Green enchiladas with chicken',
        'HUEVOS RANCHEROS': 'Huevos rancheros',
        'HUEVOS A LA MEXICANA': 'Mexican-style eggs',
        'HUEVOS REVUELTOS C/JAMON': 'Scrambled eggs with ham',
        'HUEVOS AL GUSTO': 'Eggs any style',
        'HUEVOS ESTRELLADOS': 'Fried eggs',
        'HUEVOS C/JAMON O TOCINO': 'Eggs with ham or bacon',
        'OMELETTE DE QUESO': 'Cheese omelette',
        'MOLLETES': 'Molletes',
        'HOT CAKES': 'Pancakes',
        'HOT CAKES C/TOCINO': 'Pancakes with bacon',
        'FRUTA DE TEMPORADA': 'Seasonal fruit',
        'PLATO DE FRUTA': 'Fruit plate',
        'YOGURT CON GRANOLA': 'Yogurt with granola',
        'PAN TOSTADO': 'Toast',
      });
    });

    test('soups and mains', () {
      expectEnglish({
        'POZOLE': 'Pozole',
        'POZOLE ROJO GDE': 'Red pozole, large',
        'SOPA DE TORTILLA': 'Tortilla soup',
        'SOPA AZTECA': 'Tortilla soup',
        'SOPA DE VERDURAS': 'Vegetable soup',
        'SOPA DEL DIA': 'Soup of the day',
        'CONSOME DE POLLO': 'Chicken consommé',
        'CALDO DE POLLO': 'Chicken soup',
        'CREMA DE ELOTE': 'Cream of corn soup',
        'CREMA DE CHAMPIÑONES': 'Cream of mushroom soup',
        'MOLE CON POLLO': 'Mole with chicken',
        'COCHINITA PIBIL': 'Cochinita pibil',
        'CHILES EN NOGADA': 'Chiles en nogada',
        'ARRACHERA 200GR': 'Skirt steak 200 g',
        'PECHUGA A LA PLANCHA': 'Grilled chicken breast',
        'PECHUGA EMPANIZADA': 'Breaded chicken breast',
        'MILANESA DE POLLO': 'Chicken milanesa',
        'FAJITAS DE POLLO': 'Chicken fajitas',
        'FILETE DE PESCADO': 'Fish fillet',
        'PESCADO A LA VERACRUZANA': 'Veracruz-style fish',
        'CAMARONES AL MOJO DE AJO': 'Shrimp in garlic sauce',
        'COCTEL DE CAMARON': 'Shrimp cocktail',
        'CEVICHE DE PESCADO': 'Fish ceviche',
        'TOSTADA DE CEVICHE': 'Ceviche tostada',
        'ARROZ BLANCO': 'White rice',
        'FRIJOLES REFRITOS': 'Refried beans',
        'ORDEN FRIJOLES CHARROS': 'Order of charro beans',
        'ENSALADA CESAR C/POLLO': 'Caesar salad with chicken',
        'ENS. MIXTA': 'Mixed salad',
        'COMIDA CORRIDA': 'Set lunch',
        'CARNITAS 250GR': 'Carnitas 250 g',
        'BARBACOA 1/2 KG': 'Barbacoa 1/2 kg',
        'MEDIA DOCENA DE OSTIONES': 'Half dozen oysters',
      });
    });

    test('desserts', () {
      expectEnglish({
        'HELADO DE VAINILLA': 'Vanilla ice cream',
        'COPA DE HELADO': 'Ice cream sundae',
        'NIEVE DE LIMON': 'Lime sorbet',
        'ARROZ CON LECHE': 'Rice pudding',
        'FLAN': 'Flan',
        'FRESAS CON CREMA': 'Strawberries with cream',
      });
    });
  });

  group('fast food', () {
    test('burgers, pizza, chicken', () {
      expectEnglish({
        'HAMBURGUESA': 'Burger',
        'HAMBURGUESA C/QUESO': 'Burger with cheese',
        'HAMB. DOBLE C/QUESO': 'Double burger with cheese',
        'HAMB CLASICA': 'Classic burger',
        'HAMBURGUESA CON PAPAS': 'Burger with fries',
        'COMBO 1': 'Combo 1',
        'COMBO HAMBURGUESA': 'Burger combo',
        'HOT DOG': 'Hot dog',
        'HOT DOG JUMBO': 'Hot dog, jumbo',
        'NUGGETS 10 PZAS': 'Nuggets 10 pieces',
        'ALITAS BBQ': 'BBQ wings',
        'BONELESS BUFFALO': 'Buffalo boneless wings',
        'POLLO FRITO 2 PZAS': 'Fried chicken 2 pieces',
        '2 PZAS POLLO': '2 pieces of chicken',
        '1/2 POLLO ROSTIZADO': '1/2 rotisserie chicken',
        'PIZZA HAWAIANA': 'Hawaiian pizza',
        'PIZZA PEPPERONI MED': 'Pepperoni pizza, medium',
        'PIZZA 4 QUESOS': 'Four-cheese pizza',
        'PIZZA MARGARITA': 'Margherita pizza',
        '2 REBANADAS DE PIZZA': '2 slices of pizza',
        'CLUB SANDWICH C/PAPAS': 'Club sandwich with fries',
        'EXTRA QUESO': 'Extra cheese',
        'S/CEBOLLA': 'Without onion',
        'C/TODO': 'With everything',
      });
    });

    test('fries are fries, never potatoes or popes', () {
      expectEnglish({
        'PAPAS': 'Fries',
        'PAPAS FRITAS': 'Fries',
        'PAPAS A LA FRANCESA': 'French fries',
        'PAPAS A LA FRANCESA GDE': 'French fries, large',
        'PAPAS GDE': 'Fries, large',
        'PAPAS MED': 'Fries, medium',
        'ORDEN DE PAPAS': 'Order of fries',
        'PAPA AL HORNO': 'Baked potato',
      });
    });
  });

  group('bars', () {
    test('beer', () {
      expectEnglish({
        'CERVEZA': 'Beer',
        'CERVEZA CORONA': 'Corona beer',
        'CERV VICTORIA': 'Victoria beer',
        'CERV. MODELO ESPECIAL': 'Modelo Especial beer',
        'MODELO ESPECIAL 355 ML': 'Modelo Especial 355 ml',
        'NEGRA MODELO BOT': 'Negra Modelo, bottle',
        'CORONA EXTRA': 'Corona Extra',
        'DOS EQUIS AMBAR': 'Dos Equis amber',
        'XX LAGER': 'Dos Equis lager',
        'CERVEZA DE BARRIL': 'Draught beer',
        'CERVEZA OSCURA': 'Dark beer',
        'CERVEZA NACIONAL': 'Domestic beer',
        'CERVEZA IMPORTADA': 'Imported beer',
        'CUBETA DE CERVEZA': 'Bucket of beer',
        'TARRO DE CERVEZA': 'Mug of beer',
        'MICHELADA': 'Michelada',
        '2X1 CERVEZA': '2x1 beer',
      });
    });

    test('wine, spirits and cocktails', () {
      expectEnglish({
        'COPA DE VINO TINTO': 'Glass of red wine',
        'COPA VINO BLANCO': 'Glass of white wine',
        'VINO TINTO COPA': 'Red wine, glass',
        'BOTELLA DE VINO BLANCO': 'Bottle of white wine',
        'COPA DE VINO DE LA CASA': 'Glass of house wine',
        'MARGARITA': 'Margarita',
        'PALOMA': 'Paloma',
        'MOJITO': 'Mojito',
        'PIÑA COLADA': 'Piña colada',
        'CARAJILLO': 'Carajillo',
        'CUBA LIBRE': 'Cuba libre',
        'GIN TONIC': 'Gin and tonic',
        'MEZCAL': 'Mezcal',
        'TEQUILA DON JULIO': 'Don Julio tequila',
        'TEQUILA DON JULIO REPOSADO': 'Don Julio reposado tequila',
        'DON JULIO 70': 'Don Julio 70',
        'TEQUILA DERECHO': 'Tequila neat',
        'CABALLITO DE TEQUILA': 'Shot of tequila',
        'RON CON COCA': 'Rum with Coca-Cola',
        'WHISKY': 'Whisky',
        'SANGRIA': 'Sangria',
      });
    });
  });

  group('hotel and room service', () {
    test('breakfast and the tray', () {
      expectEnglish({
        'DESAYUNO BUFFET': 'Buffet breakfast',
        'DESAYUNO BUFFET ADULTO': 'Adult buffet breakfast',
        'DESAYUNO AMERICANO': 'American breakfast',
        'DESAYUNO CONTINENTAL': 'Continental breakfast',
        'CLUB SANDWICH': 'Club sandwich',
        'SANDWICH CLUB': 'Club sandwich',
        'SPAGHETTI A LA BOLOÑESA': 'Spaghetti bolognese',
        'PASTA ALFREDO': 'Pasta Alfredo',
        'FILETE DE SALMON': 'Salmon fillet',
        'SALMON A LA PLANCHA': 'Grilled salmon',
        'RIB EYE 400 GR': 'Rib-eye steak 400 g',
        'NEW YORK 350GR': 'New York strip steak 350 g',
        'NEW YORK CHEESECAKE': 'New York cheesecake',
        'ENSALADA DE FRUTAS': 'Fruit salad',
        'SERVICIO A CUARTOS': 'Room service',
        'SERVICIO A HABITACION': 'Room service',
        'CARGO POR SERVICIO': 'Service charge',
        'PROPINA': 'Tip',
      });
    });
  });

  group('convenience stores', () {
    test('packets, bottles and cans', () {
      expectEnglish({
        'SABRITAS': 'Sabritas',
        'GANSITO': 'Gansito',
        'GALLETAS OREO': 'Oreo cookies',
        'CHOCOLATE HERSHEY': "Hershey's chocolate",
        'KIT KAT': 'KitKat',
        'M&M': "M&M's",
        'PAN BIMBO': 'Bimbo bread',
        'GATORADE NARANJA': 'Gatorade orange',
        'ELECTROLIT FRESA': 'Electrolit strawberry',
        'JUGO DEL VALLE': 'Del Valle juice',
        'BOING MANGO': 'Boing mango',
        'PEÑAFIEL MINERAL 600 ML': 'Peñafiel sparkling 600 ml',
        'HIELO 5KG': 'Ice 5 kg',
        'BOLSA DE HIELO': 'Bag of ice',
        'BOLSA': 'Bag',
      });
    });

    test('what is not food or drink is not guessed', () {
      expectNotRead(['CIGARROS', 'MARLBORO ROJO', 'PILAS AA', 'RECARGA TELCEL']);
    });
  });

  group('Guatemala and El Salvador', () {
    test('typical dishes', () {
      expectEnglish({
        'PUPUSA DE QUESO': 'Cheese pupusa',
        'PUPUSAS REVUELTAS': 'Pupusas revueltas',
        'PUPUSA DE FRIJOL CON QUESO': 'Bean pupusa with cheese',
        'PUPUSA QUESO C/LOROCO': 'Cheese pupusa with loroco',
        'PUPUSA DE CHICHARRON': 'Chicharrón pupusa',
        'CURTIDO': 'Curtido (pickled cabbage)',
        'CASAMIENTO': 'Casamiento (rice and beans)',
        'PLATANOS FRITOS': 'Fried plantains',
        'PLATANO FRITO C/CREMA': 'Fried plantain with cream',
        'DESAYUNO CHAPIN': 'Desayuno chapín (Guatemalan breakfast)',
        'DESAYUNO TIPICO': 'Traditional breakfast',
        'PEPIAN DE POLLO': 'Chicken pepián',
        'JOCON': 'Jocón',
        'HILACHAS': 'Hilachas',
        'CHUCHITOS': 'Chuchitos',
        'TAMAL DE POLLO': 'Chicken tamal',
        'TAMALES': 'Tamales',
        'FRIJOLES VOLTEADOS': 'Refried black beans',
        'CHURRASCO': 'Churrasco',
        'POLLO ASADO': 'Grilled chicken',
        'PAN CON POLLO': 'Pan con pollo (chicken sandwich)',
      });
    });

    test('drinks', () {
      expectEnglish({
        'FRESCO DE TAMARINDO': 'Tamarind drink',
        'FRESCO NATURAL': 'Natural fruit drink',
        'FRESCO': 'Fruit drink',
        'ATOL DE ELOTE': 'Atol de elote (hot sweetcorn drink)',
        'LICUADO DE BANANO': 'Banana smoothie',
        'LICUADO DE PAPAYA CON LECHE': 'Papaya smoothie with milk',
        'CAFE NEGRO': 'Black coffee',
        'KOLASHAMPAN': 'Kolashampan',
        'PILSENER': 'Pilsener',
        'CERVEZA GALLO': 'Gallo beer',
        'GALLO 355ML': 'Gallo 355 ml',
      });
    });
  });

  group('Venezuela and Colombia', () {
    test('Venezuela', () {
      expectEnglish({
        'AREPA REINA PEPIADA': 'Arepa reina pepiada',
        'AREPA DE QUESO': 'Cheese arepa',
        'AREPA PELUA': 'Arepa pelúa',
        'AREPA CON QUESO DE MANO': 'Arepa with queso de mano',
        'CACHAPA C/QUESO': 'Cachapa with cheese',
        'TEQUEÑOS': 'Tequeños',
        'TEQUENOS 6 PZAS': 'Tequeños 6 pieces',
        'EMPANADA DE CARNE': 'Meat empanada',
        'EMPANADAS DE POLLO': 'Chicken empanadas',
        'PABELLON CRIOLLO': 'Pabellón criollo',
        'HALLACA': 'Hallaca',
        'JUGO DE PARCHITA': 'Passion fruit juice',
        'JUGO DE GUANABANA': 'Soursop juice',
        'PAPELON CON LIMON': 'Papelón con limón (sugar-cane limeade)',
        'MERENGADA DE FRESA': 'Strawberry milkshake',
        'BATIDO DE MANGO': 'Mango shake',
        'MARRON GRANDE': 'Marrón (coffee with milk), large',
        'GUAYOYO': 'Guayoyo (black coffee)',
        'CAFE CON LECHE GRANDE': 'Coffee with milk, large',
        'MALTIN POLAR': 'Maltín Polar',
        'POLAR LIGHT': 'Polar Light',
        'PERRO CALIENTE': 'Hot dog',
      });
    });

    test('Colombia', () {
      expectEnglish({
        'TINTO': 'Black coffee (tinto)',
        'TINTO PEQUEÑO': 'Black coffee (tinto), small',
        'CAFE TINTO': 'Black coffee',
        'AROMATICA': 'Herbal tea',
        'BANDEJA PAISA': 'Bandeja paisa',
        'AJIACO': 'Ajiaco',
        'SANCOCHO': 'Sancocho',
        'AREPA DE CHOCLO': 'Sweetcorn arepa',
        'PANDEBONO': 'Pandebono',
        'ALMOJABANA': 'Almojábana',
        'PATACON CON QUESO': 'Patacón with cheese',
        'PATACONES': 'Patacones',
        'CHORIPAN': 'Choripán',
        'JUGO DE MORA': 'Blackberry juice',
        'JUGO DE LULO EN AGUA': 'Lulo juice in water',
        'JUGO DE MARACUYA EN LECHE': 'Passion fruit juice in milk',
        'LIMONADA DE COCO': 'Coconut lemonade',
        'GASEOSA': 'Soft drink',
        'GASEOSA POSTOBON': 'Postobón soft drink',
        'CERVEZA AGUILA': 'Águila beer',
        'CLUB COLOMBIA': 'Club Colombia',
        'AGUARDIENTE': 'Aguardiente',
      });
    });
  });

  group('words that mean something else here', () {
    test('torta is a sandwich in Mexico, a cake only with a sweet flavour',
        () {
      expectEnglish({
        'TORTA DE JAMON': 'Ham sandwich',
        'TORTA DE MILANESA': 'Milanesa sandwich',
        'TORTA DE PIERNA': 'Roast pork sandwich',
        'TORTA CUBANA': 'Torta cubana',
        'TORTA AHOGADA': 'Torta ahogada',
        'TORTA DE CHOCOLATE': 'Chocolate cake',
      });
    });

    test('tinto is wine next to wine and coffee on its own', () {
      expectEnglish({
        'VINO TINTO': 'Red wine',
        'COPA DE TINTO': 'Glass of red wine',
        'TINTO DE VERANO': 'Tinto de verano',
        'TINTO': 'Black coffee (tinto)',
      });
    });

    test('cola is the drink, but not after "de res"', () {
      expectEnglish({
        'COLA LIGHT': 'Light cola',
        'COLA DE RES': 'Oxtail',
        'COLA DE LANGOSTA': 'Lobster tail',
      });
    });

    test('americano is a coffee, and American behind food', () {
      expectEnglish({
        'AMERICANO': 'Americano',
        'CAFE AMERICANO C/LECHE': 'Americano with milk',
        'QUESO AMERICANO': 'American cheese',
        'HAMBURGUESA AMERICANA': 'American burger',
      });
    });

    test('helado is ice cream, and iced behind a drink', () {
      expectEnglish({
        'HELADO': 'Ice cream',
        'TE HELADO': 'Iced tea',
      });
    });

    test('"te" is tea only as a whole word', () {
      expectEnglish({'TE': 'Tea', 'TE LIMON': 'Lime tea'});
      expectNotRead(['TE QUIERO', 'TECATE ROJA TITANIUM']);
    });

    test('an abbreviation is read by what stands next to it', () {
      expectEnglish({
        'AGUA JAM': 'Hibiscus water',
        'TORTA JAM': 'Ham sandwich',
        'LECHE DESC': 'Skimmed milk',
        'DESC EMPLEADO': 'Employee discount',
        'MALTEADA C FRESA': 'Milkshake with strawberry',
        'CAPUCHINO M': 'Cappuccino M',
      });
    });

    test('names with no settled English are left to the user', () {
      expectNotRead([
        'PAN DE ELOTE',
        'PAN FRANCES',
        'CREMA DE WHISKY',
        'PURE DE CAMOTE AL TEQUILA REPOSADO DON NACHO',
      ]);
      expectEnglish({
        'PURE DE PAPA': 'Mashed potato',
        'PURE DE MANZANA': 'Apple purée',
        'FRUTA FRESCA': 'Fresh fruit',
      });
    });
  });

  group('lines the dictionary must not answer', () {
    test('one unknown word is enough', () {
      expectNotRead([
        'MALTEADA DOÑA TOTA',
        'PARIS WARM BOWL',
        'VT Berry Pearls Lem',
        'HAMBURGUESA LA PATRONA',
        'TACOS EL GÜERO',
        'ENSALADA TROPICANA',
        'MICHELADA CUBANA',
        'WHISKY 12 AÑOS',
        'DORITOS NACHO',
        'PIZZA 1/2 HAWAIANA 1/2 PEPPERONI',
        'POLLO A LA NARANJA',
        'TACOS A PASTOR',
      ]);
    });

    test('totals, payment and table lines are not items', () {
      expectNotRead([
        'TOTAL',
        'SUBTOTAL',
        'IVA 16%',
        'EFECTIVO',
        'TARJETA',
        'MESA 12',
        'CAMBIO',
        'CAMBIO 50.00',
        'ENTRADA GENERAL',
        '123456',
        '',
      ]);
    });

    test('only Spanish is in the dictionary', () {
      expect(ItemLexicon.translate('CAFE COM LEITE', 'pt'), isNull);
      expect(ItemLexicon.translate('CAFE CON LECHE', 'pt'), isNull);
      expect(ItemLexicon.translate('CAFE CON LECHE', 'en'), isNull);
    });
  });

  group('what the scanner does to the words', () {
    test('lost accents, mixed case and stray marks', () {
      expectEnglish({
        'Café Americano Gde': 'Americano, large',
        'PIÑA COLADA': 'Piña colada',
        'PINA COLADA': 'Piña colada',
        'Jugo de Naranja': 'Orange juice',
        'TÉ HELADO': 'Iced tea',
      });
    });

    test('digits read for letters, letters for each other', () {
      expectEnglish({
        'C0CA COLA 600ML': 'Coca-Cola 600 ml',
        '5PRITE': 'Sprite',
        'JUG0 DE NARANJA': 'Orange juice',
        'LEOHE ENTERA': 'Whole milk',
        'POIIO ASADO': 'Grilled chicken',
        'QUESADILIA': 'Quesadilla',
        'CAME ASADA': 'Carne asada (grilled beef)',
      });
    });

    test('words split, glued and cut short', () {
      expectEnglish({
        'REFRE SCO 887 ML': 'Soft drink 887 ml',
        'C HOCOLATE CALIENTE': 'Hot chocolate',
        'CERVE ZA': 'Beer',
        'AGUAMINERAL': 'Mineral water',
        'SINHIELO': 'Without ice',
        'HAMBURG C/QUESO': 'Burger with cheese',
      });
    });
  });

  group('what kind of thing a line is', () {
    test('drink, food, or neither', () {
      expect(ItemLexicon.kindOf('MALTEADA C CHOCOLATE CH'), ItemKind.drink);
      expect(ItemLexicon.kindOf('COLA 887 ML'), ItemKind.drink);
      expect(ItemLexicon.kindOf('TE VERDE'), ItemKind.drink);
      expect(ItemLexicon.kindOf('L. ENTERA'), ItemKind.drink);
      expect(ItemLexicon.kindOf('VASO DE AGUA'), ItemKind.drink);
      expect(ItemLexicon.kindOf('PAPAS FAM'), ItemKind.food);
      expect(ItemLexicon.kindOf('PASTEL DE CAFE'), ItemKind.food);
      expect(ItemLexicon.kindOf('HELADO DE TE VERDE'), ItemKind.food);
      expect(ItemLexicon.kindOf('COLA DE RES'), ItemKind.food);
      expect(ItemLexicon.kindOf('VASO DESECHABLE'), ItemKind.other);
      expect(ItemLexicon.kindOf('MINERAL'), ItemKind.other);
      expect(ItemLexicon.kindOf('PARA LLEVAR'), ItemKind.other);
      expect(ItemLexicon.kindOf('PROPINA'), ItemKind.other);
    });

    test('unknown wording has no kind', () {
      expect(ItemLexicon.kindOf('PARIS WARM BOWL'), isNull);
      expect(ItemLexicon.kindOf('MARLBORO ROJO'), isNull);
      expect(ItemLexicon.kindOf('TOTAL'), isNull);
      expect(ItemLexicon.kindOf('CAFE CON LECHE', 'pt'), isNull);
    });

    test('a choice or an extra for the item above', () {
      for (final line in [
        'VASO DESECHABLE',
        'CAMBIO L. LIGHT',
        'EXTRA CREMA BATIDA 20GR',
        'EXTRA QUESO',
        'MINERAL',
        'SIN HIELO',
        'S/CEBOLLA',
        'PARA LLEVAR',
        'C/LECHE DESL',
      ]) {
        expect(ItemLexicon.isOption(line), isTrue, reason: line);
      }
      for (final line in [
        'MALTEADA C CHOCOLATE CH',
        'LIMONADA',
        'TACOS AL PASTOR',
        'PARIS WARM BOWL',
      ]) {
        expect(ItemLexicon.isOption(line), isFalse, reason: line);
      }
    });
  });

  group('the dictionary itself', () {
    test('no wording has two different meanings', () {
      expect(ItemLexicon.conflicts, isEmpty);
    });

    test('is a real dictionary, not a handful of words', () {
      expect(ItemLexicon.entryCount, greaterThan(1000));
    });

    test('every answer starts with a capital and has no stray spaces', () {
      for (final line in [
        'MALTEADA C CHOCOLATE CH',
        'agua mineral 600ml',
        '  TACOS   AL  PASTOR  ',
        '2X1 CERVEZA',
        'L. ENTERA',
      ]) {
        final english = ItemLexicon.translate(line, 'es')!;
        expect(english, english.trim(), reason: line);
        expect(english.contains('  '), isFalse, reason: line);
        expect(english[0], english[0].toUpperCase(), reason: line);
      }
    });
  });

  group('wording written out for the translation model', () {
    test('abbreviations are written in full, the rest is kept', () {
      expect(ItemLexicon.expand('MALTEADA C CHOCOLATE CH DOÑA TOTA', 'es'),
          'MALTEADA con CHOCOLATE chico DOÑA TOTA');
      expect(ItemLexicon.expand('HAMB. LA PATRONA C/QUESO GDE', 'es'),
          'hamburguesa LA PATRONA con QUESO grande');
    });

    test('nothing to write out: the line is returned untouched', () {
      expect(ItemLexicon.expand('PARIS WARM BOWL', 'es'), 'PARIS WARM BOWL');
      expect(ItemLexicon.expand('Desc. 10% AICM', 'pt'), 'Desc. 10% AICM');
    });
  });
}
