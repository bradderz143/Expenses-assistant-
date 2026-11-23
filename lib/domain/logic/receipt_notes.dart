import 'text_normaliser.dart';

/// What a note is about; decides its icon.
enum ReceiptNoteKind { invoice, tip, discount, offer, wifi, toilet, returns }

/// Something printed on a receipt that is worth knowing about: how to get a
/// tax invoice, whether the tip is included, an offer for next time, the
/// Wi-Fi password. Shown to the user only, never exported.
class ReceiptNote {
  const ReceiptNote(this.kind, this.title, {this.detail, this.printed});

  final ReceiptNoteKind kind;

  /// Plain English, e.g. "Tax invoice (factura): ask within 30 days".
  final String title;

  /// More in English: a web address, a password, how to do it.
  final String? detail;

  /// The wording on the receipt it came from.
  final String? printed;

  @override
  String toString() => 'ReceiptNote($kind, $title, $detail)';
}

/// Finds [ReceiptNote]s in the text read from a receipt, by fixed rules, so
/// it works offline and says nothing it cannot back up.
class ReceiptNotes {
  ReceiptNotes._();

  static RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false);

  static final RegExp _web = _re(
    r'(https?://\S+|www\.\S+|\b[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|mx|net|org|cloud|'
    r'app|co|ve|sv|es|br)(\.[a-z]{2})?(/\S*)?)',
  );
  static final RegExp _days = _re(r'(\d{1,3})\s*d[ií]as|(\d{1,3})\s*days');
  static final RegExp _price = RegExp(r'\d[.,]\d{2}\b');

  static final RegExp _invoice = _re(r'factur|\bcfdi\b|\binvoice\b|nota\s+fiscal');
  static final RegExp _atPurchase = _re(
    r'(al|en\s+el)\s+momento|mismo\s+d[ií]a|at\s+the\s+time\s+of',
  );
  static final RegExp _sameMonth = _re(r'(mismo|dentro\s+del?)\s+mes|same\s+month');

  static final RegExp _tipNotIncluded = _re(
    r'(propina|servicio)\s+no\s+(est[aá]\s+)?incluid|'
    r'no\s+incluye\s+(la\s+)?(propina|servicio)|'
    r'(tip|gratuity|service)\s+(is\s+)?not\s+included',
  );
  static final RegExp _tipIncluded = _re(
    r'(propina|servicio)\s+(ya\s+)?(est[aá]\s+)?incluid|'
    r'incluye\s+(la\s+)?(propina|servicio)|'
    r'(tip|gratuity|service(\s+charge)?)\s+(is\s+)?(already\s+)?included',
  );

  static final RegExp _offer = _re(
    r'\bgratis\b|\bfree\b|descuento|discount|\d{1,2}\s?%\s?(de\s+desc|off)|'
    r'\b2\s?x\s?1\b|cup[oó]n|coupon|promoci[oó]n|\bpromo\b|regalo|cortes[ií]a|'
    r'pr[oó]xima\s+visita|next\s+visit|encuesta|survey|\bpuntos\b|recompensa|'
    r'reward',
  );
  static final RegExp _survey = _re(r'encuesta|survey|opini[oó]n|feedback');
  static final RegExp _free = _re(r'\bgratis\b|\bfree\b|regalo|cortes[ií]a');
  static final RegExp _discount =
      _re(r'descuento|discount|\d{1,2}\s?%|\b2\s?x\s?1\b|cup[oó]n|coupon');
  static final RegExp _points = _re(r'\bpuntos\b|recompensa|reward|\bpoints\b');
  static final RegExp _nextVisit = _re(r'pr[oó]xima\s+visita|next\s+visit');

  static final RegExp _wifi = _re(r'wi-?\s?fi|\binternet\b|\bssid\b|\bred\s*:');
  static final RegExp _password = _re(
    r'(password|contrase[ñn]a|clave|pass|pwd)\s*:?\s*(\S+)',
  );
  static final RegExp _network = _re(
    r'(?:wi-?\s?fi|internet|ssid|red|network)\s*:?\s*([A-Za-z0-9][\w\-. ]{1,30}?)'
    r'(?=\s*(?:password|contrase|clave|pass\b|pwd|$))',
  );

  static final RegExp _toilet =
      _re(r'sanitario|\bba[ñn]os?\b|\bwc\b|restroom|toilet|\baseo');
  static final RegExp _code = RegExp(r'\b(\d{3,6}\s?[#*]?)(?!\d)');

  static final RegExp _returns =
      _re(r'devoluci|\bcambios\b|reembolso|refund|\breturns?\b');

  /// The notes for a receipt read as [rows], at most one of each kind.
  static List<ReceiptNote> find(List<String> rows) {
    final lines = [
      for (final r in rows) TextNormaliser.collapseSpaces(r),
    ].where((l) => l.isNotEmpty).toList();
    final notes = <ReceiptNote>[];
    void add(ReceiptNote? note) {
      if (note != null && notes.every((n) => n.kind != note.kind)) {
        notes.add(note);
      }
    }

    add(_invoiceNote(lines));
    add(_tipNote(lines));
    add(_discountNote(lines));
    add(_offerNote(lines));
    add(_wifiNote(lines));
    add(_toiletNote(lines));
    add(_returnsNote(lines));
    return notes;
  }

  /// The row at [i] and the running text round it (a sentence the printer
  /// wrapped over several lines).
  static List<String> _paragraph(List<String> lines, int i, {int reach = 3}) {
    bool prose(String l) => !_price.hasMatch(l) && l.length >= 6;
    var start = i;
    while (start > 0 && i - start < reach && prose(lines[start - 1]) &&
        !lines[start - 1].trimRight().endsWith('.')) {
      start--;
    }
    var end = i;
    while (end + 1 < lines.length && end - i < reach && prose(lines[end + 1]) &&
        !lines[end].trimRight().endsWith('.')) {
      end++;
    }
    return lines.sublist(start, end + 1);
  }

  /// A web address that is about something else: the privacy notice, or
  /// the survey when looking for the invoice site.
  static final RegExp _otherSite = _re(r'privacidad|privacy|aviso\s+legal');

  /// "www.example. com. mx/": OCR puts spaces round the dots of an address.
  static String _joinAddress(String line) => line
      .replaceAllMapped(
        _re(r'\s*\.\s*(?=(com|mx|net|org|cloud|app|gob|co|ve|sv|es|br|gt)\b)'),
        (_) => '.',
      )
      .replaceAllMapped(_re(r'(www)\s*\.\s*(?=\w)'), (m) => '${m[1]}.')
      .replaceAllMapped(_re(r'(https?)\s*:\s*/\s*/\s*'), (m) => '${m[1]}://');

  static String? _webIn(List<String> lines, {RegExp? notAbout}) {
    for (var i = 0; i < lines.length; i++) {
      final line = _joinAddress(lines[i]).replaceAll(_email, ' ');
      final m = _web.firstMatch(line);
      if (m == null) continue;
      final context = '${i > 0 ? lines[i - 1] : ''} ${lines[i]}';
      if (_otherSite.hasMatch(context)) continue;
      if (notAbout != null && notAbout.hasMatch(context)) continue;
      return m[0]!.replaceAll(RegExp(r'[.,;:)]+$'), '');
    }
    return null;
  }

  /// "Folio para facturar: 0543104092632357", "Referencia de facturacion:"
  /// with the number on the next line: the reference the invoice site asks
  /// for.
  static final RegExp _folioLabel = _re(
    r'(?:folio|ticket|referencia|ref\.?|clave|c[oó]digo|id)\s+(?:de\s+|para\s+)?'
    r'factur(?:aci[oó]n|ar|a)\b\s*:?\s*(.*)$',
  );
  static final RegExp _folioValue = RegExp(r'^[A-Z0-9][A-Z0-9\- ]{3,40}$');

  static String? _folioIn(List<String> lines) {
    String? value(String text) {
      final t = text.trim();
      if (!_folioValue.hasMatch(t.toUpperCase())) return null;
      // A reference is mostly digits; words after the label are not one.
      final digits = RegExp(r'\d').allMatches(t).length;
      if (digits < 4 || digits * 2 < t.replaceAll(' ', '').length) return null;
      return t.replaceAll(' ', '');
    }

    for (var i = 0; i < lines.length; i++) {
      final m = _folioLabel.firstMatch(lines[i]);
      if (m == null) continue;
      final same = value(m[1]!);
      if (same != null) return same;
      if (m[1]!.trim().isEmpty && i + 1 < lines.length) {
        final next = value(lines[i + 1]);
        if (next != null) return next;
      }
    }
    return null;
  }

  static final RegExp _email =
      RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+');

  static int? _daysIn(Iterable<String> lines) {
    for (final l in lines) {
      final m = _days.firstMatch(l);
      if (m != null) return int.tryParse(m[1] ?? m[2]!);
    }
    return null;
  }

  static ReceiptNote? _invoiceNote(List<String> lines) {
    final first = lines.indexWhere(_invoice.hasMatch);
    if (first < 0) return null;
    // Invoice wording is often spread over a few short paragraphs.
    final end = first + 8 < lines.length ? first + 8 : lines.length;
    final window = lines.sublist(first > 0 ? first - 1 : 0, end);
    final days = _daysIn(window);
    final web = _webIn(window, notAbout: _survey);
    final folio = _folioIn(window);
    String? email;
    for (final l in window) {
      final m = _email.firstMatch(_joinAddress(l));
      if (m != null) {
        email = m[0];
        break;
      }
    }
    // Joined: "solicitela en el" / "momento de la compra" wraps.
    final joined = window.join(' ');
    final atPurchase = _atPurchase.hasMatch(joined);
    final sameMonth = _sameMonth.hasMatch(joined);
    final when = days != null
        ? 'request it within $days days'
        : sameMonth
            ? 'request it within the same month'
            : atPurchase
                ? 'ask for it when paying'
                : null;
    final steps = [
      if (atPurchase && days != null) 'Ask at the till when paying, or',
      if (web != null) 'Online: $web',
      if (folio != null) 'Invoice reference (folio): $folio',
      if (email != null) 'Invoice help: $email',
    ];
    return ReceiptNote(
      ReceiptNoteKind.invoice,
      'Tax invoice (factura)${when == null ? ' available' : ': $when'}',
      detail: [
        ...steps,
        'Your company may need it for the claim.',
      ].join('\n'),
      printed: window
          .where((l) => _invoice.hasMatch(l) || _days.hasMatch(l) || _atPurchase.hasMatch(l))
          .join(' '),
    );
  }

  static ReceiptNote? _tipNote(List<String> lines) {
    for (final l in lines) {
      if (_tipNotIncluded.hasMatch(l)) {
        return ReceiptNote(
          ReceiptNoteKind.tip,
          'Tip not included in the total',
          printed: l,
        );
      }
    }
    for (final l in lines) {
      if (_tipIncluded.hasMatch(l)) {
        return ReceiptNote(
          ReceiptNoteKind.tip,
          'Tip or service already included',
          detail: 'No need to tip again.',
          printed: l,
        );
      }
    }
    return _tipPaid(lines);
  }

  static final RegExp _money =
      RegExp(r'(-?)\s?\$?\s?((?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2})(-?)\s*$');

  /// "Propina Tarjeta \$18.65": a tip that was added, with its amount. A
  /// blank or zero tip line and a table of suggested tips say nothing.
  static final RegExp _tipLine =
      _re(r'^\W*(propina|tip|gratuity|gratificaci[oó]n)\b(?!\s*(sugerid|suggest))');

  static ReceiptNote? _tipPaid(List<String> lines) {
    for (final l in lines) {
      if (!_tipLine.hasMatch(l) || l.contains('%')) continue;
      final m = _money.firstMatch(l);
      if (m == null || m[1] == '-' || m[3] == '-') continue;
      final digits = m[2]!.replaceAll(RegExp(r'[.,]'), '');
      if (int.tryParse(digits) == 0) continue;
      return ReceiptNote(
        ReceiptNoteKind.tip,
        'Tip on this receipt: ${m[2]}',
        detail: 'Check whether your company wants tips claimed separately.',
        printed: l,
      );
    }
    return null;
  }

  /// "1 Desc. 10% AICM -41.50": a discount already taken off this bill.
  static final RegExp _discountLine = _re(
    r'^\W*(?:\d{1,2}\s+)?(desc\.?|descuento|dscto\.?|dto\.?|discount|promoci[oó]n|'
    r'promo|cortes[ií]a|cup[oó]n|coupon)\b',
  );

  static ReceiptNote? _discountNote(List<String> lines) {
    for (final l in lines) {
      if (!_discountLine.hasMatch(l)) continue;
      final m = _money.firstMatch(l);
      if (m == null) continue;
      final digits = m[2]!.replaceAll(RegExp(r'[.,]'), '');
      if (int.tryParse(digits) == 0) continue;
      final percent = RegExp(r'(\d{1,2})(?:[.,]\d+)?\s?%').firstMatch(l)?[1];
      return ReceiptNote(
        ReceiptNoteKind.discount,
        'Discount already applied: ${percent == null ? '' : '$percent% '}'
            '(-${m[2]})',
        detail: 'The amount paid is after this discount.',
        printed: l,
      );
    }
    return null;
  }

  static ReceiptNote? _offerNote(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      // A discount already taken off this bill is in the amounts.
      if (!_offer.hasMatch(l) || _price.hasMatch(l)) continue;
      final paragraph = _paragraph(lines, i);
      final text = paragraph.join(' ');
      final survey = _survey.hasMatch(text);
      final free = _free.hasMatch(text);
      final next = _nextVisit.hasMatch(text);
      // A survey with nothing in it for the customer is not worth a note.
      if (survey && !free && !_discount.hasMatch(text) && !_points.hasMatch(text)) {
        continue;
      }
      final title = survey && free
          ? 'Answer the survey for something free${next ? ' next visit' : ''}'
          : survey
              ? 'Survey offer on the receipt'
              : _discount.hasMatch(text)
                  ? 'Discount offer${next ? ' for your next visit' : ''}'
                  : free
                      ? 'Free item offer${next ? ' for your next visit' : ''}'
                      : _points.hasMatch(text)
                          ? 'Rewards points'
                          : next
                              ? 'Offer for your next visit'
                              : 'Promotion on the receipt';
      // The survey's address usually follows the offer.
      final after = lines.sublist(
          i, i + 4 < lines.length ? i + 4 : lines.length);
      final web = _webIn([...paragraph, ...after]);
      return ReceiptNote(
        ReceiptNoteKind.offer,
        title,
        detail: web == null ? null : 'Online: $web',
        printed: text,
      );
    }
    return null;
  }

  static ReceiptNote? _wifiNote(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (!_wifi.hasMatch(lines[i])) continue;
      final near = [
        lines[i],
        if (i + 1 < lines.length) lines[i + 1],
      ];
      final password = near
          .map(_password.firstMatch)
          .firstWhere((m) => m != null, orElse: () => null)?[2];
      if (password == null) continue;
      final network = _network.firstMatch(lines[i])?[1]?.trim();
      return ReceiptNote(
        ReceiptNoteKind.wifi,
        'Wi-Fi password',
        detail: [
          if (network != null && network.isNotEmpty) 'Network: $network',
          'Password: $password',
        ].join('\n'),
        printed: near.join(' '),
      );
    }
    return null;
  }

  static ReceiptNote? _toiletNote(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (!_toilet.hasMatch(lines[i])) continue;
      final near = [
        lines[i],
        if (i + 1 < lines.length) lines[i + 1],
      ];
      for (final l in near) {
        final code = _code.firstMatch(l.substring(
            l == lines[i] ? _toilet.firstMatch(l)!.end : 0));
        if (code != null) {
          return ReceiptNote(
            ReceiptNoteKind.toilet,
            'Toilet code: ${code[1]!.replaceAll(' ', '')}',
            printed: near.join(' '),
          );
        }
      }
    }
    return null;
  }

  static ReceiptNote? _returnsNote(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (!_returns.hasMatch(lines[i])) continue;
      final paragraph = _paragraph(lines, i);
      final days = _daysIn(paragraph);
      return ReceiptNote(
        ReceiptNoteKind.returns,
        days == null
            ? 'Returns policy printed on the receipt'
            : 'Returns or exchanges within $days days',
        printed: paragraph.join(' '),
      );
    }
    return null;
  }
}
