// Doubles in fields of objects.
import 'dart:math';

class Body {
  double x, y, z, vx, vy, vz;
  final double mass;
  Body(this.x, this.y, this.z, this.vx, this.vy, this.vz, this.mass);
}

const solarMass = 4 * pi * pi, days = 365.24;

List<Body> bodies() => [
  Body(0, 0, 0, 0, 0, 0, solarMass),
  Body(
    4.84143144246472090, -1.16032004402742839, -0.103622044471123109, //
    0.00166007664274403694 * days, 0.00769901118419740425 * days,
    -0.0000690460016972063023 * days, 0.000954791938424326609 * solarMass,
  ),
  Body(
    8.34336671824457987, 4.12479856412430479, -0.403523417114321381, //
    -0.00276742510726411021 * days, 0.00499852801234917238 * days,
    0.0000230417297573763929 * days, 0.000285885980666130812 * solarMass,
  ),
  Body(
    12.8943695621391310, -15.1111514016986312, -0.223307578892655734, //
    0.00296460137564761618 * days, 0.00237847173959480950 * days,
    -0.0000296589568540237556 * days, 0.0000436624404335156298 * solarMass,
  ),
  Body(
    15.3796971148509165, -25.9193146099879641, 0.179258772950371181, //
    0.00268067772490389322 * days, 0.00162824170038242295 * days,
    -0.0000951592254519715870 * days, 0.0000515138902046611451 * solarMass,
  ),
];

void advance(List<Body> all, double dt) {
  for (var i = 0; i < all.length; i++) {
    final a = all[i];
    for (var j = i + 1; j < all.length; j++) {
      final b = all[j];
      final dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
      final square = dx * dx + dy * dy + dz * dz;
      final force = dt / (square * sqrt(square));
      a.vx -= dx * b.mass * force;
      a.vy -= dy * b.mass * force;
      a.vz -= dz * b.mass * force;
      b.vx += dx * a.mass * force;
      b.vy += dy * a.mass * force;
      b.vz += dz * a.mass * force;
    }
  }
  for (final a in all) {
    a.x += dt * a.vx;
    a.y += dt * a.vy;
    a.z += dt * a.vz;
  }
}

double energy(List<Body> all) {
  var sum = 0.0;
  for (var i = 0; i < all.length; i++) {
    final a = all[i];
    sum += 0.5 * a.mass * (a.vx * a.vx + a.vy * a.vy + a.vz * a.vz);
    for (var j = i + 1; j < all.length; j++) {
      final b = all[j];
      final dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
      sum -= a.mass * b.mass / sqrt(dx * dx + dy * dy + dz * dz);
    }
  }
  return sum;
}

void main() {
  final all = bodies();
  print(energy(all).toStringAsFixed(9));
  for (var i = 0; i < 2000000; i++) {
    advance(all, 0.01);
  }
  print(energy(all).toStringAsFixed(9));
}
