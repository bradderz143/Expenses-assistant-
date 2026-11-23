import 'dart:io';

import 'package:expense_assistant/application/capture_receipt.dart';
import 'package:expense_assistant/application/commands.dart';
import 'package:expense_assistant/application/package_service.dart';
import 'package:expense_assistant/application/translate_items.dart';
import 'package:expense_assistant/data/db/app_database.dart';
import 'package:expense_assistant/data/repositories/sqlite_repositories.dart';
import 'package:expense_assistant/data/services/file_storage_service.dart';
import 'package:expense_assistant/domain/entities/enums.dart';
import 'package:expense_assistant/domain/entities/receipt.dart';
import 'package:expense_assistant/domain/logic/item_classifier.dart';
import 'package:expense_assistant/domain/logic/item_lexicon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'domain_logic_test.dart' show elFogonRows;
import 'workflow_test.dart' show FakeOcr, FakePdf, FakeTranslation;

/// Remembers what was sent to the translation model.
class RecordingTranslation extends FakeTranslation {
  final List<String> sent = [];

  @override
  Future<List<String>> translateAll(
    List<String> texts, {
    required String from,
    String to = 'en',
  }) async {
    sent.addAll(texts);
    // The model answers in lower case, as it does for sentence-case input.
    return [for (final t in texts) 'english of ${t.toLowerCase()}'];
  }
}

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

    test('restaurant bill with names cut to the column', () {
      expectEnglish({
        'Lengua al Gusto': 'Tongue any style',
        'Agua Topo Chico': 'Topo Chico water',
        'Naranjada': 'Orangeade',
        'Clamato Natural': 'Clamato natural',
        'Cuervo Reposado': 'Cuervo reposado',
        'Pastel 3 Leches': 'Tres leches cake',
        'Mousse Guanaban': 'Soursop mousse',
        'Espres Dob Regu': 'Double espresso, regular',
        'Espres Regular': 'Espresso, regular',
        'Cafe de Olla': 'Café de olla (spiced coffee)',
      });
      // Too little left of the words to be sure.
      expectNotRead(['F Res Sal Q/Cab', 'Pechu Mol Verde', 'Paste 3 Leches']);
    });

    test('coffee-shop ticket read with damage', () {
      expectEnglish({
        'Caramel Iced WVhip L Media': 'Caramel iced whip L, medium',
        'Chocolate Frappe Grandę': 'Chocolate frappe, large',
      });
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
        'PAPAS MEDIANAS': 'Fries, medium',
        'PAPAS GRANDES': 'Fries, large',
        'Papas Chicas gratis': 'Free fries, small',
        'EXTRA PAPAS': 'Extra fries',
        'ORDEN DE PAPAS': 'Order of fries',
        'PAPA AL HORNO': 'Baked potato',
        'PAPAS AL HORNO': 'Baked potatoes',
      });
    });

    test('the marks tills put in front of extras and counts', () {
      expectEnglish({
        '+ TOCINO EXTRA': 'Extra bacon',
        '- SIN CEBOLLA': 'Without onion',
        '* CON LECHE': 'With milk',
        'TACO AL PASTOR x2': 'Taco al pastor x2',
        'TACO PASTOR C/Q': 'Taco al pastor with cheese',
        'HAMBURGUESA S/CEBOLLA': 'Burger without onion',
        'LIMONADA S/HIELO': 'Lemonade without ice',
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

    test('brand names are kept, not translated ("rested raven")', () {
      expectEnglish({
        'HERRADURA REPOSADO': 'Herradura reposado',
        'CENTENARIO PLATA': 'Centenario silver',
        'CERVEZA SOL': 'Sol beer',
        'CARTA BLANCA': 'Carta Blanca',
        'RON CACIQUE': 'Cacique rum',
        'AGUARDIENTE ANTIOQUEÑO': 'Antioqueño aguardiente',
        'AGUA SALVAVIDAS': 'Salvavidas water',
        'AGUA SANTA MARIA 600ML': 'Santa María water 600 ml',
        'CHOCOLATE ABUELITA': 'Abuelita chocolate',
        'SANGRIA SEÑORIAL': 'Sangría Señorial',
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
        'RIBEYE STEAK': 'Rib-eye steak',
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
        'LECHE LALA 1L': 'Lala milk 1 L',
        'CAFE MOLIDO 400G': 'Ground coffee 400 g',
        'ARROZ 1KG': 'Rice 1 kg',
        'FRIJOL NEGRO 1KG': 'Black beans 1 kg',
        'JAMON DE PAVO 250G': 'Turkey ham 250 g',
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

    test('the country of the receipt decides', () {
      String? inCountry(String line, String country) =>
          ItemLexicon.translate(line, 'es', country: country);
      // A torta is a sandwich at the Mexican table, a cake further south.
      expect(inCountry('TORTA DE JAMON', 'Mexico'), 'Ham sandwich');
      expect(inCountry('TORTA', 'Guatemala'), 'Sandwich');
      expect(inCountry('TORTA ESPECIAL', 'El Salvador'), 'Special sandwich');
      expect(inCountry('TORTA', 'Venezuela'), 'Cake');
      expect(inCountry('PORCION DE TORTA', 'Colombia'), 'Portion of cake');
      expect(inCountry('TORTA DE BANANO', 'Colombia'), 'Banana cake');
      expect(inCountry('TORTA DE CHOCOLATE', 'Mexico'), 'Chocolate cake');
      // Tostadas are crisp tortillas there, toast here.
      expect(inCountry('TOSTADA DE CEVICHE', 'Mexico'), 'Ceviche tostada');
      expect(inCountry('TOSTADAS', 'Colombia'), 'Toast');
      expect(inCountry('TOSTADAS FRANCESAS', 'Colombia'), 'French toast');
      // A tinto on its own.
      expect(inCountry('TINTO', 'Colombia'), 'Black coffee (tinto)');
      expect(inCountry('TINTO', 'Mexico'), 'Red wine');
      expect(inCountry('COPA DE TINTO', 'Colombia'), 'Glass of red wine');
      // Everything else reads the same everywhere.
      expect(inCountry('MALTEADA C CHOCOLATE CH', 'Venezuela'),
          'Milkshake with chocolate, small');
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
        'PAN DE ELOTE GDE',
        'REBANADA PAN DE ELOTE',
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

    test('a stroke or a letter that could stand for something else', () {
      // "S/" inside a dish name: a mango sauce, not a salmon without mango.
      expectNotRead(['Salmon S/Mango', 'TACO C/X', 'CAFE A']);
      // On its own line under the item it is a choice.
      expectEnglish({'S/MANGO': 'Without mango'});
    });

    test('numbers and codes that only look like items', () {
      expectNotRead([
        'CAJA: 19',
        'REF 004512',
        'REF',
        'XX 1234',
        'XX*** X*****',
        'LITROS: 35.214',
        'CH 2',
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

  group('in the app', () {
    late AppDatabase db;
    late Directory temp;
    late FileStorageService storage;
    late FakeOcr ocr;
    late SqliteReceiptRepository receipts;
    late SqliteTranslationRepository translations;
    late SqlitePackageRepository packages;
    late SqliteSettingsRepository settings;
    late PackageService packageService;
    late RecordingTranslation model;
    late TranslateItemsUseCase translate;
    late Receipt receipt;
    var ids = 0;
    DateTime clock() => DateTime(2026, 11, 23, 9);

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      db = await AppDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      temp = await Directory.systemTemp.createTemp('lexicon_test');
      storage = FileStorageService(Directory(p.join(temp.path, 'Expenses')));
      await storage.ensureStructure();
      ocr = FakeOcr();
      receipts = SqliteReceiptRepository(db.db);
      final trips = SqliteTripRepository(db.db);
      translations = SqliteTranslationRepository(db.db);
      packages = SqlitePackageRepository(db.db);
      settings = SqliteSettingsRepository(db.db);
      packageService = PackageService(
        receipts: receipts,
        trips: trips,
        translations: translations,
        packages: packages,
        storage: storage,
        pdfRenderer: FakePdf(),
        clock: clock,
      );
      model = RecordingTranslation();
      translate = TranslateItemsUseCase(
        receipts: receipts,
        translations: translations,
        packages: packages,
        packageService: packageService,
        settings: settings,
        storage: storage,
        ocr: ocr,
        translator: model,
        clock: clock,
      );
      // A meal receipt, so the crop is read as items.
      ocr.enqueueRows(elFogonRows);
      final photo = File(p.join(temp.path, 'IMG_0001.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      final captured = await CaptureReceiptUseCase(
        receipts: receipts,
        trips: trips,
        settings: settings,
        storage: storage,
        ocr: ocr,
        translation: FakeTranslation(),
        packages: packageService,
        idGenerator: () => 'id-${++ids}',
        clock: clock,
      )(photo.path);
      receipt = await ReceiptCommands(
        receipts: receipts,
        packages: packages,
        packageService: packageService,
        storage: storage,
        clock: clock,
      ).saveDetails(captured.receipt.copyWith(
        category: 'Meals Overseas',
        description: 'Lunch whilst attending a workshop',
      ));
    });

    tearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    Future<TranslationDraft> read(List<String> rows) {
      ocr.enqueueRows(rows);
      final crop = File(p.join(temp.path, 'crop.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      return translate.prepare(receipt: receipt, croppedImagePath: crop.path);
    }

    test('known items get the dictionary\'s English as a fixed translation '
        'and never reach the model', () async {
      final draft = await read([
        '1 MALTEADA C CHOCOLATE CH 79.00',
        '1 NUTELLA LATTE FRAPPE GD 95.00',
        '1 PAPAS FAM 62.00',
        '1 COLA 887 ML 38.00',
        'TOTAL 274.00',
      ]);
      expect(draft.lines.map((l) => l.translatedText).toList(), [
        'Milkshake with chocolate, small',
        'Nutella latte frappe, large',
        'Fries, family size',
        'Cola 887 ml',
      ]);
      // Shown as a fixed translation, not "Machine translation: check it".
      expect(draft.lines.map((l) => l.engine).toSet(),
          {TranslationEngine.glossary});
      expect(draft.lines.map((l) => l.category).toList(), [
        ItemCategory.drink,
        ItemCategory.drink,
        ItemCategory.food,
        ItemCategory.drink,
      ]);
      expect(model.sent, isEmpty);
      expect(draft.warning, isNull);
    });

    test('the user\'s saved wording wins over the dictionary', () async {
      await translations.rememberGlossary(
          'es', 'papas fam', 'Family fries to share');
      final draft = await read([
        '4 TACOS AL PASTOR 220.00',
        '1 PAPAS FAM 62.00',
        '1 LIMONADA 45.00',
      ]);
      expect(draft.lines.map((l) => l.translatedText).toList(), [
        'Pork tacos (al pastor)', // seeded glossary
        'Family fries to share', // saved by the user
        'Lemonade', // dictionary
      ]);
      expect(model.sent, isEmpty);
    });

    test('a line with an unknown word goes to the model in sentence case '
        'with abbreviations written out', () async {
      final draft = await read([
        '1 MALTEADA C CHOCOLATE CH DOÑA TOTA 79.00',
        '1 HAMB. LA PATRONA C/QUESO GDE 145.00',
        '1 LIMONADA 45.00',
      ]);
      expect(model.sent, [
        'Malteada con chocolate chico doña tota',
        'Hamburguesa la patrona con queso grande',
      ]);
      expect(draft.lines.map((l) => l.translatedText).toList(), [
        'English of malteada con chocolate chico doña tota',
        'English of hamburguesa la patrona con queso grande',
        'Lemonade',
      ]);
      expect(draft.lines.map((l) => l.engine).toList(), [
        TranslationEngine.onDevice,
        TranslationEngine.onDevice,
        TranslationEngine.glossary,
      ]);
      // What the till printed is still what the user sees as the original.
      expect(draft.lines.first.originalText,
          'MALTEADA C CHOCOLATE CH DOÑA TOTA');
    });

    test('the receipt\'s country reaches the dictionary', () async {
      receipt = receipt.copyWith(country: 'Colombia');
      await receipts.upsert(receipt);
      final draft = await read([
        '1 PORCION DE TORTA 12.00',
        '1 TINTO 3.00',
      ]);
      expect(draft.lines.map((l) => l.translatedText).toList(),
          ['Portion of cake', 'Black coffee (tinto)']);
    });

    test('a choice goes with the item above it, priced or not', () async {
      final draft = await read([
        '1 LIMONADA 45.00',
        'MINERAL',
        '1 VASO DESECHABLE 2.00',
        '1 HAMBURGUESA C/QUESO 120.00',
        '1 EXTRA QUESO 15.00',
        '1 PARA LLEVAR 5.00',
        '1 PASTEL DE CAFE 60.00',
      ]);
      expect({
        for (final l in draft.lines) l.translatedText: l.category,
      }, {
        'Lemonade': ItemCategory.drink,
        'Sparkling': ItemCategory.drink,
        'Disposable cup': ItemCategory.drink,
        'Burger with cheese': ItemCategory.food,
        'Extra cheese': ItemCategory.food,
        'To go': ItemCategory.food,
        // A cake, though "cafe" is a drink word.
        'Coffee cake': ItemCategory.food,
      });
    });
  });

  group('drink or food', () {
    test('the dictionary decides when it knows the line', () {
      expect(ItemClassifier.classify('PASTEL DE CAFE'), ItemCategory.food);
      expect(ItemClassifier.classify('HELADO DE TE VERDE'), ItemCategory.food);
      expect(ItemClassifier.classify('COLA 887 ML'), ItemCategory.drink);
      expect(ItemClassifier.classify('L. ENTERA'), ItemCategory.drink);
      expect(ItemClassifier.classify('CERV. VICTORIA'), ItemCategory.drink);
      expect(ItemClassifier.classify('COLA DE RES'), ItemCategory.food);
    });

    test('otherwise the drink words do, as before', () {
      expect(ItemClassifier.classify('PARIS WARM BOWL'), ItemCategory.food);
      expect(ItemClassifier.classify('SUCO DE LARANJA', '', 'pt'),
          ItemCategory.drink);
      expect(ItemClassifier.classify('XYZ 500', 'House lager'),
          ItemCategory.drink);
    });

    test('a choice names neither', () {
      expect(ItemClassifier.isChoice('VASO DESECHABLE'), isTrue);
      expect(ItemClassifier.isChoice('PARA LLEVAR'), isTrue);
      expect(ItemClassifier.isChoice('EXTRA QUESO'), isFalse); // food
      expect(ItemClassifier.isChoice('LIMONADA'), isFalse);
      expect(ItemClassifier.isChoice('PARIS WARM BOWL'), isFalse);
    });
  });

  group('wording for the translation model', () {
    test('item lines: abbreviations in full, sentence case', () {
      expect(ItemWording.forModel('MALTEADA C CHOCOLATE CH DOÑA TOTA', 'es'),
          'Malteada con chocolate chico doña tota');
      expect(ItemWording.forModel('COCA ZERO BOT XL PROMO VERANO', 'es'),
          'Coca zero botella xl promo verano');
      expect(ItemWording.forModel('PAN DE ELOTE', 'es'), 'Pan de elote');
    });

    test('capitals the till chose are kept', () {
      expect(ItemWording.sentenceCase('Pay de Queso Doña Tota'),
          'Pay de Queso Doña Tota');
      expect(ItemWording.sentenceCase('McPollo CON QUESO'), 'McPollo con queso');
      expect(ItemWording.forModel('Salmon S/Mango', 'es'), 'Salmon S/Mango');
      expect(ItemWording.forModel('Pechu Mol Verde', 'es'), 'Pechu Mol Verde');
    });

    test('other text is not read as an item: a street stays a street', () {
      expect(ItemWording.expandAbbreviations('C. REFORMA 222 S/N', 'es'),
          'C. REFORMA 222 S/N');
    });

    test('the answer opens with a capital', () {
      expect(ItemWording.capitalised('milkshake doña tota'),
          'Milkshake doña tota');
      expect(ItemWording.capitalised('2 beers'), '2 beers');
      expect(ItemWording.capitalised(''), '');
    });
  });
}
