import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  group('Vec3', () {
    test('component access and arithmetic', () {
      const v = Vec3(1, 2, 3);
      expect(v[0], 1);
      expect(v[1], 2);
      expect(v[2], 3);
      expect(v.sum, 6);
      expect(v.maxComponent, 3);
      expect(v.minComponent, 1);
      expect(v + Vec3.ones, const Vec3(2, 3, 4));
      expect(v - Vec3.ones, const Vec3(0, 1, 2));
      expect(v * 2, const Vec3(2, 4, 6));
      expect(v.hadamard(const Vec3(2, 2, 2)), const Vec3(2, 4, 6));
      expect(v.divideBy(const Vec3(2, 2, 2)), const Vec3(0.5, 1, 1.5));
      expect(v.dot(Vec3.ones), 6);
    });

    test('rejects an out-of-range index', () {
      expect(() => const Vec3(1, 2, 3)[3], throwsRangeError);
    });

    test('rejects a list of the wrong length', () {
      expect(() => Vec3.fromList(const [1, 2]), throwsArgumentError);
    });

    test('value equality', () {
      expect(const Vec3(1, 2, 3), const Vec3(1, 2, 3));
      expect(const Vec3(1, 2, 3).hashCode, const Vec3(1, 2, 3).hashCode);
      expect(const Vec3(1, 2, 3), isNot(const Vec3(1, 2, 4)));
    });
  });

  group('Mat3', () {
    test('identity leaves a vector alone', () {
      const v = Vec3(0.3, 0.6, 0.1);
      expect(Mat3.identity.apply(v), v);
    });

    test('multiplication by the identity is a no-op', () {
      const m = Mat3(1, 2, 3, 4, 5, 6, 7, 8, 10);
      expect(m * Mat3.identity, m);
      expect(Mat3.identity * m, m);
    });

    test('apply performs a row-major product', () {
      const m = Mat3(1, 2, 3, 4, 5, 6, 7, 8, 9);
      final result = m.apply(const Vec3(1, 0, 0));
      expect(result, const Vec3(1, 4, 7));
    });

    test('columns constructor places vectors in columns', () {
      final m = Mat3.columns(
        const Vec3(1, 2, 3),
        const Vec3(4, 5, 6),
        const Vec3(7, 8, 9),
      );
      expect(m.toRowMajor(), [1, 4, 7, 2, 5, 8, 3, 6, 9]);
    });

    test('diagonal applies per-channel gains', () {
      final m = Mat3.diagonal(const Vec3(2, 3, 4));
      expect(m.apply(Vec3.ones), const Vec3(2, 3, 4));
    });

    test('inverse times the original is the identity', () {
      const m = Mat3(0.72, 0.21, 0.02, 0.28, 0.80, -0.08, 0.01, -0.12, 1.20);
      final product = (m * m.inverse).toRowMajor();
      const expected = [1.0, 0, 0, 0, 1, 0, 0, 0, 1];
      for (var i = 0; i < 9; i++) {
        expect(product[i], closeTo(expected[i], 1e-12));
      }
    });

    test('a singular matrix refuses to invert', () {
      // Third row is the sum of the first two, so the determinant is zero.
      const singular = Mat3(1, 2, 3, 4, 5, 6, 5, 7, 9);
      expect(() => singular.inverse, throwsStateError);
    });

    test('rowSums is the image of a neutral', () {
      const m = Mat3(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9);
      expect(m.rowSums.x, closeTo(0.6, 1e-15));
      expect(m.apply(Vec3.ones).x, closeTo(m.rowSums.x, 1e-15));
    });

    test('transposed swaps rows and columns', () {
      const m = Mat3(1, 2, 3, 4, 5, 6, 7, 8, 9);
      expect(m.transposed.toRowMajor(), [1, 4, 7, 2, 5, 8, 3, 6, 9]);
      expect(m.transposed.transposed, m);
    });

    test('rejects a list of the wrong length', () {
      expect(() => Mat3.fromRowMajor(const [1, 2, 3]), throwsArgumentError);
    });
  });
}
