/// CIEDE2000 test data.
///
/// SOURCE REQUIRED: the full set of 34 pairs published with Sharma, Wu and
/// Dalal (2005), "The CIEDE2000 Color-Difference Formula: Implementation Notes,
/// Supplementary Test Data, and Mathematical Observations", Color Research and
/// Application 30(1), must be transcribed into this file verbatim from the
/// authors' published table before the implementation can be called verified
/// against it.
///
/// Only the single pair quoted in this project's specification is present. The
/// remaining rows are deliberately absent rather than recalled from memory:
/// inventing reference data would make the test pass while proving nothing.
/// Each row that is added must keep its original index so a failure can be
/// traced back to the published table.
library;

/// One published pair: two Lab values and the expected CIEDE2000.
typedef Ciede2000Case = ({
  int index,
  List<double> lab1,
  List<double> lab2,
  double expected,
});

/// The transcribed rows. Tolerance for comparison is 1e-4, as the paper's data
/// is published to four decimal places.
const List<Ciede2000Case> sharmaCases = [
  (
    index: 25,
    lab1: [50.0000, 2.6772, -79.7751],
    lab2: [50.0000, 0.0000, -82.7485],
    expected: 2.0425,
  ),
];

/// How many pairs the published table holds, so the test can report how much of
/// it is still missing instead of silently passing on one row.
const int sharmaPublishedCaseCount = 34;
