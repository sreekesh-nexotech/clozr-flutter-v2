import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/core/utils/upload_rules.dart';

void main() {
  test(
      'wrong type, empty and too-large files are refused with the webapp wording',
      () {
    expect(fileProblem('setup.exe', 100),
        'This file type is not accepted. Accepted: png, jpg, jpeg, gif, webp, pdf, xlsx, xls, csv, md, txt, docx, pptx.');
    expect(fileProblem('a.zip', 100),
        startsWith('This file type is not accepted'));
    expect(fileProblem('noext', 100),
        startsWith('This file type is not accepted'));
    expect(fileProblem('a.txt', 0), 'This file is empty.');
    expect(fileProblem('big.pdf', 12 * 1024 * 1024),
        'This file is 12 MB. The limit is 10 MB per file.');
    expect(fileProblem('edge.pdf', 10 * 1024 * 1024 + 1), contains('10.00 MB'));
    expect(fileProblem('ok.PDF', 1024), '');
    expect(fileProblem('exact.pdf', kUploadMaxBytes), '');
  });

  test('the name: blank refused, extension re-attached', () {
    expect(nameProblem('  ', 'a.pdf'), 'Give the file a name.');
    expect(nameProblem('Report', 'a.pdf'), '');
    expect(storedFileName('Report', 'a.PDF'), 'Report.pdf');
    expect(storedFileName('Report.pdf', 'a.pdf'), 'Report.pdf');
    expect(suggestedDisplayName('report.final.pdf'), 'report.final');
    expect(nameProblem('x' * 300, 'a.pdf'), contains('at most 255'));
  });
}
