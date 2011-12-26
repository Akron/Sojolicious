#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 52;

use_ok('Mojolicious::Plugin::XML::Atom');
use_ok('Mojolicious::Plugin::XML::GeoRSS');

my $atom = Mojolicious::Plugin::XML::Atom->new('entry');
$atom->add_extension('Mojolicious::Plugin::XML::GeoRSS');
$atom->add_author(name => 'Fry');

my $where = $atom->add_geo_where;

ok($where->add_geo_point(45.34, -23.67),'Add point');
ok(!$where->add_geo_point(45.34),'Add wrong point');
ok(!$where->add_geo_point(45.34, -23.67, 45),'Add wrong point');

ok($where->add_geo_line(45.34, -23.67, 16.3, 17.89), 'Add line');
ok($where->add_geo_line(45.34, -23.67, 16.3, 17.89, 15.4, -5.4), 'Add line');
ok(!$where->add_geo_line(45.34, -23.67), 'Add line wrong');
ok(!$where->add_geo_line(45.34, -23.67, 16.3, 17.89, 15.4), 'Add line wrong');

ok($where->add_geo_polygon(45.34, -23.67, 16.3, 17.89, 15.4, -5.4), 'Add poly');
ok($where->add_geo_polygon(45.34, -23.67, 16.3, 17.89, 15.4, -5.4, 45.34, -23.67), 'Add poly');
ok(!$where->add_geo_polygon(45.34, -23.67), 'Add poly wrong');
ok(!$where->add_geo_polygon(45.34, -23.67, 16.3, 17.89), 'Add poly wrong');
ok(!$where->add_geo_polygon(45.34, -23.67, 16.3, 17.89, 15.4, -5.4, -5.8), 'Add poly wrong');

ok($where->add_geo_box(45.34, -23.67, 16.3, 17.89), 'Add box');
ok(!$where->add_geo_box(45.34, -23.67, 16.3, 17.89, 15.4, -5.4), 'Add box wrong');
ok(!$where->add_geo_box(45.34, -23.67), 'Add box wrong');
ok(!$where->add_geo_box(45.34, -23.67, 16.3, 17.89, 15.4), 'Add box wrong');

ok($where->add_geo_circle(45.34, -23.67, 90), 'Add circle');
ok(!$where->add_geo_circle(45.34, -23.67), 'Add circle wrong');
ok(!$where->add_geo_circle(45.34, -23.67, 16.3, 17.89), 'Add circle wrong');

ok($where->add_geo_property(
  relationshipTag => 'tag1',
  featureTypeTag => [qw/tag2 tag3 tag4/],
  featureName => ['tag5'],
  foo => 'bar'
), 'Add properties');

ok($where->add_geo_floor(5), 'Add floor');
ok($where->add_geo_even(19), 'Add even');
ok($where->add_geo_radius(500), 'Add radius');


is($atom->at('point')->text, '45.34 -23.67', 'Point');
is($atom->find('line')->[0]->text, '45.34 -23.67 16.3 17.89', 'Line');
is($atom->find('line')->[1]->text, '45.34 -23.67 16.3 17.89 15.4 -5.4', 'Line');
is($atom->find('polygon')->[0]->text, '45.34 -23.67 16.3 17.89 15.4 -5.4 45.34 -23.67', 'Polygon');
is($atom->find('polygon')->[1]->text, '45.34 -23.67 16.3 17.89 15.4 -5.4 45.34 -23.67', 'Polygon');
is($atom->find('box')->[0]->text, '45.34 -23.67 16.3 17.89', 'Box');
is($atom->at('circle')->text, '45.34 -23.67 90', 'Circle');

is($atom->find('relationshipTag')->[0]->text, 'tag1', 'Property1');
ok(!$atom->find('relationshipTag')->[1], 'Property2');
my $ftt = $atom->find('featureTypeTag');
is($ftt->[0]->text, 'tag2', 'Property3');
is($ftt->[1]->text, 'tag3', 'Property4');
is($ftt->[2]->text, 'tag4', 'Property5');
ok(!$ftt->[3], 'Property6');
is($atom->find('featureName')->[0]->text, 'tag5', 'Property7');
ok(!$atom->find('featureName')->[1], 'Property8');
ok(!$atom->at('foo'), 'Property9');

is($atom->at('floor')->text, '5', 'Floor');
is($atom->at('even')->text, '19', 'Even');
is($atom->at('radius')->text, '500', 'Radius');

is($atom->at('author > name')->text, 'Fry', 'Atom Check');
my $geo_ns = 'http://www.georss.org/georss';
is($atom->at('point')->namespace, $geo_ns, 'Namespace');
is($atom->at('line')->namespace, $geo_ns, 'Namespace');
is($atom->at('box')->namespace, $geo_ns, 'Namespace');
is($atom->at('circle')->namespace, $geo_ns, 'Namespace');
is($atom->at('polygon')->namespace, $geo_ns, 'Namespace');
is($atom->at('author')->namespace, 'http://www.w3.org/2005/Atom', 'Namespace');
is($atom->at('name')->namespace, 'http://www.w3.org/2005/Atom', 'Namespace');

