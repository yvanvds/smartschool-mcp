import 'package:smartschool_mcp/src/messages/html_to_text.dart';
import 'package:smartschool_mcp/src/messages/markdown_to_html.dart';
import 'package:test/test.dart';

void main() {
  test('plain text: a blank line starts a paragraph, a line break is <br>', () {
    expect(
      markdownToHtml('Beste An,\n\nDonderdag kan ik.\nTot dan!\n\n\nJan'),
      '<p>Beste An,</p>\n<p>Donderdag kan ik.<br>Tot dan!</p>\n<p>Jan</p>',
    );
    expect(markdownToHtml('a\r\nb\r\n\r\nc'), '<p>a<br>b</p>\n<p>c</p>');
    expect(markdownToHtml('  ingesprongen  '), '<p>ingesprongen</p>');
    expect(markdownToHtml(''), '');
    expect(markdownToHtml(' \n\n '), '');
  });

  group('HTML in the text is escaped, never markup', () {
    test('tags, attributes and scripts', () {
      expect(
        markdownToHtml('<script>alert(1)</script>'),
        '<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>',
      );
      expect(
        markdownToHtml('<b onclick="steel()">hoi</b><img src=x onerror=y>'),
        '<p>&lt;b onclick=&quot;steel()&quot;&gt;hoi&lt;/b&gt;'
        '&lt;img src=x onerror=y&gt;</p>',
      );
    });

    test('character references and quotes', () {
      expect(
        markdownToHtml('Tom & Jerry: "5 < 6" en \'&amp;\''),
        '<p>Tom &amp; Jerry: &quot;5 &lt; 6&quot; en &#39;&amp;amp;&#39;</p>',
      );
    });

    test('inside bold, italic, list items and link text', () {
      expect(
        markdownToHtml('**<i>x</i>** *<u>*\n- <li>\n\n[<b>](https://a.be)'),
        '<p><strong>&lt;i&gt;x&lt;/i&gt;</strong> <em>&lt;u&gt;</em></p>\n'
        '<ul><li>&lt;li&gt;</li></ul>\n'
        '<p><a href="https://a.be">&lt;b&gt;</a></p>',
      );
    });

    test('in a link address, which cannot break out of the attribute', () {
      expect(
        markdownToHtml('[x](https://a.be/?q="><script>)'),
        '<p><a href="https://a.be/?q=&quot;&gt;&lt;script&gt;">x</a></p>',
      );
      expect(
        markdownToHtml('[site](https://a.be/?b=1&c=2)'),
        '<p><a href="https://a.be/?b=1&amp;c=2">site</a></p>',
      );
    });

    test('links other than http, https and mailto stay as written', () {
      expect(
        markdownToHtml(
          '[a](javascript:alert(1)) [b](javascript:x) '
          '[c](data:text/html,x) [d](ftp://a.be) [e](/relatief)',
        ),
        '<p>[a](javascript:alert(1)) [b](javascript:x) '
        '[c](data:text/html,x) [d](ftp://a.be) [e](/relatief)</p>',
      );
      expect(
        markdownToHtml('[mail](mailto:an@school.be) [web](HTTP://A.BE)'),
        '<p><a href="mailto:an@school.be">mail</a> '
        '<a href="HTTP://A.BE">web</a></p>',
      );
    });
  });

  test('bold and italic, not inside words or around spaces', () {
    expect(
      markdownToHtml('**vet** en *schuin* en __ook vet__ en _ook schuin_'),
      '<p><strong>vet</strong> en <em>schuin</em> en '
      '<strong>ook vet</strong> en <em>ook schuin</em></p>',
    );
    expect(
      markdownToHtml('***allebei*** en **[link](https://a.be/a_b_c)**'),
      '<p><strong><em>allebei</em></strong> en '
      '<strong><a href="https://a.be/a_b_c">link</a></strong></p>',
    );
    expect(
      markdownToHtml('5 * 3 * 2, file_name_v2, snake__case, * of **'),
      '<p>5 * 3 * 2, file_name_v2, snake__case, * of **</p>',
    );
  });

  test('bulleted and numbered lists, with continuation lines', () {
    expect(
      markdownToHtml(
        'Mee te brengen:\n'
        '- pennenzak\n'
        '* **rekenmachine**\n'
        '  (niet grafisch)\n'
        '+ cursus\n'
        '\n'
        '1. lezen\n'
        '2) oefenen\n'
        'Succes!',
      ),
      '<p>Mee te brengen:</p>\n'
      '<ul><li>pennenzak</li><li><strong>rekenmachine</strong><br>'
      '(niet grafisch)</li><li>cursus</li></ul>\n'
      '<ol><li>lezen</li><li>oefenen</li></ol>\n'
      '<p>Succes!</p>',
    );
    expect(
      markdownToHtml('3. drie\n4. vier\n- los'),
      '<ol start="3"><li>drie</li><li>vier</li></ol>\n<ul><li>los</li></ul>',
    );
  });

  test('headings and code stay as the text they are', () {
    expect(markdownToHtml('# Titel\n`code`'), '<p># Titel<br>`code`</p>');
  });

  test('read back with htmlToText (what read_message shows), the text is '
      'what was written', () {
    const text =
        'Beste An,\n\nDonderdag kan ik, **na 16 uur**.\n'
        'Tot dan & groetjes <Jan>';
    expect(
      htmlToText(markdownToHtml(text)),
      'Beste An,\n\nDonderdag kan ik, na 16 uur.\nTot dan & groetjes <Jan>',
    );
    expect(
      htmlToText(markdownToHtml('Lijst:\n- een\n- twee\n\n1. drie')),
      'Lijst:\n\n- een\n- twee\n\n1. drie',
    );
  });
}
