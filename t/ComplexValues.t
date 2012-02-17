use Test::More tests => 131;
use strict;
use warnings;

$|++;

use lib 'lib';
use lib '../lib';

use_ok 'Sojolicious::Oro';
use_ok 'Sojolicious::ComplexValues';

my $db_file = ':memory:';

my $cv = Sojolicious::ComplexValues->new(
  oro => Sojolicious::Oro->new($db_file),
  name => 'Resource'
);

ok($cv, 'Create Complex Value');

ok($cv->init_db, 'Initialize database');

my $u_obj = {
  name => 'Akron',
  size => [40,45],
  value => {
    foobar => 1,
    tree => 2
  }};

# Create and Read
my $obj_id;
ok($obj_id = $cv->create($u_obj), 'Create resource');

my $u_obj_2 = $cv->read({id => $obj_id});

is($u_obj_2->{totalResults}, 1, 'Total Results');
is($u_obj_2->{startIndex}, 0, 'StartIndex');
is($u_obj_2->{entry}->{name}, 'Akron', 'Name');
is($u_obj_2->{entry}->{size}->[0], 40, 'Size 1');
is($u_obj_2->{entry}->{size}->[1], 45, 'Size 1');
is($u_obj_2->{entry}->{value}->{foobar}, 1, 'Value 1');
is($u_obj_2->{entry}->{value}->{tree}, 2, 'Value 2');
is($u_obj_2->{entry}->{id}, $obj_id, 'ID');

$u_obj_2 = $cv->read({id => 3});
is($u_obj_2->{startIndex}, 0, 'StartIndex');
is($u_obj_2->{totalResults}, 0, 'Total Results');

$u_obj = {
  name => 'Homer',
  value => {
    foobar => 3,
    tree => 4
  },
  urls => [
    {
      href => 'http://sojolicio.us/',
      rel => 'home'
    },
    {
      href => 'http://work.sojolicio.us/',
      rel => 'work'
    }
  ]};

$obj_id = $cv->create($u_obj);
my $obj_id_2 = $cv->create({  fun => 'hihi' });
$u_obj_2 = $cv->read({id => 3});
is($u_obj_2->{startIndex}, 0, 'StartIndex');
is($u_obj_2->{totalResults}, 1, 'Total Results');

ok($u_obj_2 = $cv->read({
  filterBy => 'urls.rel',
  filterOp => 'equals',
  filterValue => 'work',
  fields => 'urls'
}), 'read');

is($u_obj_2->{entry}->[0]->{urls}->[0]->{rel}, 'home', 'Read');

# New
$cv = Sojolicious::ComplexValues->new(
  oro => Sojolicious::Oro->new($db_file),
  name => 'Resource'
);

$cv->init_db;

ok($cv->create({
  name => 'Akron',
  age => '40',
  value => {
    'top' => 12,
    'bottom' => 19
  }}), 'Create');

ok($cv->create({
  name => 'Peter',
  age => '42',
  value => {
    'top' => 10,
    'bottom' => 30
  }}), 'Create');

ok($cv->create({
  name => 'Merlin',
  age => '76',
  value => {
    'top' => 12,
    'bottom' => 28
  }}), 'Create');

ok($cv->create({
  name => 'Henrike',
  age => '61',
  value => {
    'top' => 12,
    'bottom' => 18
  }}), 'Create');

my $fry_id;
ok($fry_id = $cv->create({
  name => 'Fry',
  age => '20',
  value => {
    'top' => 12,
    'bottom' => 18
  }}), 'Create');


my %request = (
  'filterBy' => 'value.top',
  'filterOp' => 'equals',
  'filterValue' => 12,
  'sortBy'      => 'age',
  'sortOrder'   => 'descending',
  'startIndex'  => 1,
  'count'       => 2,
  'fields'      => 'age,name'
);

my $response = $cv->read( {%request });

is($response->{totalResults}, 4, 'Total Results');
is($response->{itemsPerPage}, 2, 'Items per page');
is($response->{startIndex}, 1, 'Start Index');
is($response->{entry}->[0]->{name}, 'Henrike', 'Name');
is($response->{entry}->[1]->{name}, 'Akron', 'Name');
is($response->{entry}->[0]->{age}, 61, 'Age');
is($response->{entry}->[1]->{age}, 40, 'Age');
is($response->{entry}->[0]->{id}, 4, 'ID');
is($response->{entry}->[1]->{id}, 1, 'ID');
ok(!exists $response->{entry}->[0]->{value}, 'Value');
ok(!exists $response->{entry}->[1]->{value}, 'Value');
ok(!defined $response->{entry}->[2], 'Entry');


my $fry = $cv->read({ id => $fry_id });
my $updated = $fry->{entry}->{updated};

sleep(2);

# Update
ok($cv->update({
  id => $fry_id,
  age => 21,
  value => {
    top => undef
  }}), 'Update');

ok($response = $cv->read({ id => $fry_id }), 'Read');
is($response->{entry}->{age}, 21, 'Age');
ok(!exists $response->{entry}->{value}->{top}, 'Top');
isnt($response->{entry}->{updated}, $updated, 'Updated');

ok( $response = $cv->read, 'Read without arguments');
is( $response->{totalResults}, 5, 'Total results');

ok( $response = $cv->read({ updatedSince => $updated }), 'UpdatedSince');
is( $response->{totalResults}, 1, 'Total results');

ok( $response = $cv->read({
  filterBy    => 'name',
  filterOp    => 'startswith',
  filterValue => 'H',
  fields      => 'id'
}), 'name filter');

is( $response->{totalResults}, 1, 'Total results');

my $del_id = $response->{entry}->[0]->{id};
ok( $cv->delete($del_id), 'Delete');

ok( $response = $cv->read, 'Read');

is( $response->{totalResults}, 4, 'Total results');

ok( $response = $cv->read({ id => $del_id }), 'Read deleted');

is( $response->{totalResults}, 0, 'Total results');

my $test_id;
ok($test_id = $cv->create({
  name => 'Chad',
  age => '24',
  value => {
    'top' => 14,
    'bottom' => 19
  }}), 'Create');

isnt($test_id, $del_id, 'ID Check');

# Multiple ids
ok($response = $cv->read({id => [1, 3]}), 'Multiple IDs');
is($response->{totalResults},2, 'Total results');

ok($response = $cv->read({id => '1,3'}), 'Multiple IDs');
is($response->{totalResults},2, 'Total results');

ok($response = $cv->read({
  id => '-',
  filterBy    => 'name',
  filterOp    => 'startswith',
  filterValue => 'F',
}), 'Request ID');

is($response->{id}, 5, 'ID');

ok($response = $cv->read({
  id          => '---',
  filterBy    => 'value.top',
  filterOp    => 'equals',
  filterValue => 12,
}), 'Request ID');

is_deeply($response->{id}, [1,3], 'IDs');


# -----------
# Transaction

my $oro = $cv->oro;
ok($oro->txn(
  sub {

    my ($top, $bottom) = (0,0);
    foreach (1..20) {
      $cv->create({
	name => 'Henrike',
	age => '16',
	value => {
	  'top' => $top++,
	  'bottom' => $bottom += 3
	}
      });
    };
  }), 'Transaction');


# Deletion
# --------

ok($response = $cv->read({
  filterBy => 'value.top',
  filterOp => 'equals',
  filterValue => 9
}), 'Read');

is ($response->{totalResults}, 1, 'TotalResults');

my $all;
ok($all = $cv->read({ count => 100 }), 'All users');
is ($all->{totalResults}, 25, 'TotalResults');

ok($cv->delete($response->{entry}->[0]->{id}), 'Delete');

ok($all = $cv->read({ count => 100 }), 'All users');
is ($all->{totalResults}, 24, 'TotalResults');

ok($response = $cv->read({
  filterBy => 'value.top',
  filterOp => 'equals',
  filterValue => 14
}), 'Read');

ok($cv->delete($response->{entry}->[0]->{id}), 'Delete');

ok($all = $cv->read({ count => 100 }), 'All users');
is ($all->{totalResults}, 23, 'TotalResults');

ok($all = $cv->read({
  filterBy => 'name',
  filterOp => 'equals',
  filterValue => 'Henrike',
  id => '---'
}), 'All Henrikes');

ok($cv->delete($all->{id}), 'Delete');

ok($all = $cv->read({ count => 100 }), 'All users');
is ($all->{totalResults}, 13, 'TotalResults');


# Update
# --------
ok($response = $cv->read({
  filterBy => 'name',
  filterOp => 'equals',
  filterValue => 'Akron'
}), 'Akron');

is ($response->{totalResults}, 1, 'TotalResults');

my $entry = $response->{entry}->[0];
my $id    = $entry->{id};
my $time  = $entry->{updated};

is($entry->{value}->{top}, 12, 'Value.top old');
is($entry->{value}->{bottom}, 19, 'Value.bottom old');
is($entry->{age}, 40, 'Age old');

ok($cv->update({
  id => $id,
  age => '41',
  value => {
    top => 14,
    bottom => undef
  }
}), 'Update');


ok($response = $cv->read({ id => $id }), 'Akron by id');

is ($response->{totalResults}, 1, 'TotalResults');

$entry = $response->{entry};

is($entry->{value}->{top}, 14, 'Value.top new');
ok(!exists $entry->{value}->{bottom}, 'Value.bottom new');
is($entry->{age}, 41, 'Age new');
ok($entry->{updated} != $time, 'Updated');


ok($cv->update({
  id => $id,
  tags => ['+name','+programmer','+guy','-test']
}), 'Update');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
is(scalar @{$entry->{tags}}, 3, 'Tags');

ok($cv->update({
  id => $id,
  tags => ['-name','type']
}), 'Update');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
is(scalar @{$entry->{tags}}, 2, 'Tags');


ok($cv->update({
  id => $id,
  tags => ['-programmer','-guy']
}), 'Update');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
ok(!exists $entry->{tags}, 'Tags');

ok($cv->update({
  id => $id,
  urls => [
    {
      '+href' => 'http://sojolicio.us/',
      '+rel' => 'home'
    }
  ]
}), 'Update');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
is($entry->{urls}->[0]->{rel}, 'home', 'Url');
is($entry->{urls}->[0]->{href}, 'http://sojolicio.us/', 'Url');

ok($cv->update({
  id => $id,
  urls => [
    {
      '-href' => 'http://sojolicio.us/',
    }
  ]
}), 'Update with delete');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
ok(!exists $entry->{urls}, 'Url');

ok($cv->update({
  id => $id,
  urls => [
    {
      '+href' => 'http://sojolicio.us/',
      '+rel' => 'home'
    }
  ]
}), 'Update');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
is($entry->{urls}->[0]->{rel}, 'home', 'Url');
is($entry->{urls}->[0]->{href}, 'http://sojolicio.us/', 'Url');

ok($cv->update({
  id => $id,
  urls => undef
}), 'Update with undef');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
ok(!exists $entry->{urls}, 'Url');

ok($cv->update({
  id => $id,
  value => { top => undef }
}), 'Update with undef');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
ok(!exists $entry->{value}, 'Value');

ok(!$cv->update({
  id => $id,
  value => { top => undef }
}), 'Update with undef');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
ok(!exists $entry->{value}, 'Value');

ok($cv->update({
  id => $id,
  urls => [
    {
      '+href' => 'http://sojolicio.us/',
      '+rel' => 'home'
    },
    {
      '+href' => 'http://work.sojolicio.us/',
      '+rel' => 'work'
    }
  ],
}), 'Update with undef');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
is(@{$entry->{urls}}, 2, 'URLs');

ok($cv->update({
  id => $id,
  urls => [
    {
      '-rel' => 'work',
      'href' => 'http://work.sojolicio.us/',
    }
  ]
}), 'Update with undef');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
is(@{$entry->{urls}}, 2, 'URLs');


ok($cv->update({
  id => $id,
  urls => [
    {
      'href' => 'http://work.sojolicio.us/',
      '-href' => undef,
    }
  ]
}), 'Update with undef');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
is(@{$entry->{urls}}, 1, 'URLs');

ok($cv->update({
  id => $id,
  urls => [
    {
      '-rel' => 'home',
    }
  ]
}), 'Update with undef');

ok($entry = $cv->read({ id => $id })->{entry}, 'Akron by id');
ok(!exists $entry->{urls}, 'URLs');

__END__
