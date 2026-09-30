import 'package:smartschool_mcp/src/messages/html_to_text.dart';
import 'package:test/test.dart';

void main() {
  test('the body of the library fixture "show message.xml"', () {
    // <body>&lt;p&gt;Beste&lt;/p&gt;</body>, as XmlInterface decodes it.
    expect(htmlToText('<p>Beste</p>'), 'Beste');
  });

  test('an empty body is empty text', () {
    expect(htmlToText(''), '');
    expect(htmlToText('<p>&nbsp;</p><div><br></div>'), '');
  });

  test('paragraphs are separated by a blank line, <br> by a line break', () {
    expect(
      htmlToText(
        "<p>Beste collega's,</p><p>Morgen is er <b>oudercontact</b>."
        '<br>Tot dan!</p>',
      ),
      "Beste collega's,\n\nMorgen is er oudercontact.\nTot dan!",
    );
    expect(htmlToText('a<br><br>b'), 'a\n\nb');
  });

  test('character references are decoded and whitespace collapses', () {
    expect(
      htmlToText('<p>Caf&eacute;&nbsp;&nbsp;en &amp; &lt;test&gt;</p>'),
      'Café en & <test>',
    );
    expect(
      htmlToText('<div>\n    Een\n      twee   </div>\n<div>drie</div>'),
      'Een twee\ndrie',
    );
    expect(htmlToText('<p><b>Datum:</b> 12 maart</p>'), 'Datum: 12 maart');
    expect(htmlToText('<p>een<span> twee </span>drie</p>'), 'een twee drie');
  });

  test('empty paragraphs never leave more than one blank line', () {
    expect(
      htmlToText('<p>een</p><p>&nbsp;</p><p></p><div><br></div><p>twee</p>'),
      'een\n\ntwee',
    );
  });

  test('scripts, styles, the head and comments are dropped', () {
    expect(
      htmlToText(
        '<html><head><title>Titel</title><style>p { color: red }</style>'
        '</head><body><script>alert("x")</script><!-- verborgen -->'
        '<p>Zichtbaar</p><noscript>Geen JavaScript</noscript></body></html>',
      ),
      'Zichtbaar',
    );
  });

  test('Word markup leaves just the text', () {
    expect(
      htmlToText(
        '<!--[if gte mso 9]><xml><o:OfficeDocumentSettings>96'
        '</o:OfficeDocumentSettings></xml><![endif]-->'
        '<p class="MsoNormal"><span style="font-size:11.0pt">Hallo'
        '<o:p></o:p></span></p>'
        '<p class="MsoNormal"><o:p>&nbsp;</o:p></p>'
        '<p class="MsoNormal">Groetjes</p>',
      ),
      'Hallo\n\nGroetjes',
    );
  });

  test('links keep their address', () {
    expect(
      htmlToText(
        '<p>Zie <a href="https://example.com/info">de info</a>, '
        '<a href="https://example.com">https://example.com</a> en '
        '<a href="mailto:jan@school.be">jan@school.be</a> of '
        '<a href="mailto:jan@school.be">Jan</a>.</p>',
      ),
      'Zie [de info](https://example.com/info), https://example.com en '
      'jan@school.be of [Jan](mailto:jan@school.be).',
    );
  });

  test('links that are not absolute keep only their text', () {
    expect(
      htmlToText(
        '<p><a href="/Documents/1">intern</a> <a href="#boven">boven</a> '
        '<a href="javascript:void(0)">klik</a> <a name="anker">anker</a></p>',
      ),
      'intern boven klik anker',
    );
  });

  test('images become markers with their alt text', () {
    expect(
      htmlToText(
        '<p>Logo: <img src="a.png" alt="School logo"> '
        '<img src="b.png"></p>',
      ),
      'Logo: [image: School logo] [image]',
    );
    expect(
      htmlToText(
        '<p>Site: <a href="https://school.be">'
        '<img src="l.png" alt="Logo"></a></p>',
      ),
      'Site: [image: Logo] https://school.be',
    );
  });

  test('lists become bullet and numbered lines, nested lists indented', () {
    expect(
      htmlToText(
        '<p>Agenda:</p><ul><li>een</li><li>twee<ul><li>twee a</li>'
        '<li>twee b</li></ul></li><li>drie</li></ul>'
        '<ol><li>eerste</li><li><p>tweede</p></li></ol><p>Einde</p>',
      ),
      'Agenda:\n\n'
      '- een\n'
      '- twee\n'
      '  - twee a\n'
      '  - twee b\n'
      '- drie\n\n'
      '1. eerste\n'
      '2. tweede\n\n'
      'Einde',
    );
    expect(
      htmlToText('<ol start="3"><li>drie<br>vervolg</li><li>vier</li></ol>'),
      '3. drie\n   vervolg\n4. vier',
    );
  });

  test('headings become # lines', () {
    expect(
      htmlToText('<h1>Nieuwsbrief</h1><h3> Agenda </h3><p>Punt</p><h2></h2>'),
      '# Nieuwsbrief\n\n### Agenda\n\nPunt',
    );
  });

  test('blockquotes become > lines', () {
    expect(
      htmlToText(
        '<p>Antwoord</p><blockquote><p>Vraag 1</p><p>Vraag 2</p>'
        '</blockquote><p>Groet</p>',
      ),
      'Antwoord\n\n> Vraag 1\n>\n> Vraag 2\n\nGroet',
    );
  });

  test('table rows become lines, cells joined by |', () {
    expect(
      htmlToText(
        '<p>Rooster:</p><table><tbody>'
        '<tr><th>Dag</th><th>Uur</th></tr>'
        '<tr><td>Ma</td><td> </td><td>10u</td></tr>'
        '</tbody></table><p>Einde</p>',
      ),
      'Rooster:\n\nDag | Uur\nMa | 10u\n\nEinde',
    );
  });

  test('a horizontal rule becomes ---', () {
    expect(htmlToText('<p>a</p><hr><p>b</p>'), 'a\n\n---\n\nb');
  });

  test('<pre> keeps line breaks and indentation', () {
    expect(
      htmlToText('<p>Code:</p><pre>regel 1\n  ingesprongen\n\nregel 3</pre>'),
      'Code:\n\nregel 1\n  ingesprongen\n\nregel 3',
    );
  });

  test('a body without tags is plain text: its line breaks are kept', () {
    expect(
      htmlToText('Beste,\r\n\r\nDit is tekst &amp; meer.\nGroet\n'),
      'Beste,\n\nDit is tekst & meer.\nGroet',
    );
    expect(htmlToText('3 < 4 en 5 > 2'), '3 < 4 en 5 > 2');
  });

  test('invisible characters are removed', () {
    expect(htmlToText('<p>oud​ers­contact﻿</p>'), 'ouderscontact');
  });

  test('a realistic Smartschool body', () {
    const body = '''
<div style="font-family: Arial; font-size: 10pt;">
  <p>Beste collega's,</p>
  <p>Het oudercontact van <strong>donderdag 12 maart</strong> gaat door in
  de refter.&nbsp;Praktisch:</p>
  <ul>
    <li>Start: 17u</li>
    <li>Inschrijven via <a href="https://school.smartschool.be/planner">de planner</a></li>
  </ul>
  <p>&nbsp;</p>
  <p>Met vriendelijke groeten,<br>
  Directie</p>
  <p><img src="https://school.be/logo.png" alt="" width="120"></p>
</div>''';
    expect(
      htmlToText(body),
      "Beste collega's,\n\n"
      'Het oudercontact van donderdag 12 maart gaat door in de refter. '
      'Praktisch:\n\n'
      '- Start: 17u\n'
      '- Inschrijven via [de planner](https://school.smartschool.be/planner)'
      '\n\n'
      'Met vriendelijke groeten,\nDirectie\n\n'
      '[image]',
    );
  });
}
