#!/usr/bin/env perl
use Test::More tests => 71;
use strict;
use warnings;

use Data::Dumper;

use lib '../../lib', '../lib';
use_ok 'Sojolicious::Oro';

my $db_file = ':memory:';

my $oro = Sojolicious::Oro->new(
  $db_file => sub {
    shift->do('CREATE VIRTUAL TABLE t1 USING fts4(a, b)');
  });

ok($oro, 'Oro successfully initiated');

ok($oro->insert(
  t1 =>
    ['a','b'] =>
      (
	['transaction default models default', 'Non transaction reads'],
	['the default transaction', 'these semantics present'],
	['single request', 'default data']
      )
    ), 'Insert');

my $matchinfo;
ok($matchinfo = $oro->matchinfo('xcp'), 'Matchinfo');

my $result;
ok($result = $oro->select(
  t1 => [ [ $matchinfo => 'check' ] ] =>
    {
      t1 => { match => 'default transaction "these semantics"' }
    }
  ), 'Select with treatment');

ok($result, 'Match routine');

my $check = $result->[0]->{check};
ok($check, 'Check');
is($check->{p}, 3, 'Check p');
is($check->{c}, 2, 'Check c');
is_deeply($check->{x}->[0], [1,3,2], 'Check x[0]');
is_deeply($check->{x}->[1], [0,1,1], 'Check x[1]');
is_deeply($check->{x}->[2], [1,2,2], 'Check x[2]');
is_deeply($check->{x}->[3], [0,1,1], 'Check x[3]');
is_deeply($check->{x}->[4], [0,0,0], 'Check x[4]');
is_deeply($check->{x}->[5], [1,1,1], 'Check x[5]');

my $test = 'Check matchinfo in callback';
$oro->select(
  t1 => [ [ $matchinfo => 'check' ] ] =>
    {
      t1 => { match => 'default' }
    },
  sub {
    my $row = shift;
    is($row->{check}->{c}, 2, $test . ' 1');
    is($row->{check}->{p}, 1, $test . ' 2');
    is($row->{check}->{c}, 2, $test . ' 3');
    is($row->{check}->{x}->[0]->[1], 3, $test . ' 4');
    is($row->{check}->{x}->[1]->[1], 1, $test . ' 5');
    is($row->{check}->{x}->[1]->[2], 1, $test . ' 6');
  }
  );

ok($result = $oro->select(
  t1 =>
    [ [ $oro->matchinfo('nls') => 'check' ]] =>
      {
	t1 => { match => 'default transaction' }
      }
    ), 'Select with matchinfo');

is($result->[0]->{check}->{n}, 3, 'Check n[0]');
is($result->[1]->{check}->{n}, 3, 'Check n[1]');
is_deeply($result->[0]->{check}->{s}, [2,0], 'Check l[1]');
is_deeply($result->[1]->{check}->{s}, [1,1], 'Check l[2]');


# Offsets
ok($oro->do('CREATE VIRTUAL TABLE mail USING fts3(subject, body)'), 'Init table');
ok($oro->insert(mail => { subject => 'hello world', body => 'This message is a hello world message.' }), 'Insert');
ok($oro->insert(mail => { subject => 'urgent: serious', body => 'This mail is seen as a more serious mail' }), 'Insert');

ok($result = $oro->load(
  mail =>
    [ [ $oro->offsets => 'check' ]] =>
      {
	mail => { match => 'world' }
      }
    ), 'Select with offsets');

is($result->{check}->[0]->[2], 6, 'Byte offset');
is($result->{check}->[1]->[2], 24, 'Byte offset');


ok($oro->attach('testdb'), 'Attach temporary database');

my $doc;
ok($doc = $oro->load(t1 => ['docid:id'] => { a => { match => 'request'} }),
   'Get doc');

ok($oro->do('CREATE TABLE testdb.t2 ( name TEXT, age INTEGER, docid INTEGER )'),
   'Create table in attached database');

ok($oro->insert('testdb.t2' => {
  name => 'Akron',
  age => 24,
  docid => $doc->{id}
}), 'Insert into attached db');

ok($doc = $oro->load(
  [
    'main.t1' => ['a','b'] => { docid => 1 },
    'testdb.t2' => [qw/name age/] => { docid => 1 }
  ] => { name => 'Akron' }
), 'Get joined doc');

is($doc->{a}, 'single request', 'Check result');
is($doc->{b}, 'default data', 'Check result');
is($doc->{name}, 'Akron', 'Check result');
is($doc->{age}, 24, 'Check result');

ok($oro->detach('testdb'), 'Detach temporary database');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->load('testdb.t2' => { name => 'Akron' }),
     'Load from non-existant db');

  ok(!$oro->detach('testdb'), 'Detach non-existant db.');
}

# snippet

ok($oro->do('CREATE VIRTUAL TABLE text USING fts4()'), 'Create table');
$oro->insert(text => { content => <<TEXT });
During 30 Nov-1 Dec, 2-3oC drops.
Cool in the upper portion, minimum temperature 14-16oC
and cool elsewhere, minimum temperature 17-20oC.
Cold to very cold on mountaintops, minimum temperature 6-12oC.
Northeasterly winds 15-30 km/hr.
After that, temperature increases. Northeasterly winds 15-30 km/hr.
TEXT

my $snippet;
ok($snippet = $oro->snippet(end => '***' ), 'Create snippet 1');
ok($snippet = $oro->snippet, 'Create snippet 2');

ok($result = $oro->select(
  text => [ [ $snippet => 'example' ] ] =>
    { text => { match => 'cold' } }), 'Select with snippet');

is(index($result->[0]->{example}, '<b>...</b>cool elsewhere, '), 0,
   'Snippet equal');

ok(index($result->[0]->{example}, 'minimum temperature 6<b>...</b>') > 0,
   'Snippet equal');

ok($oro->do('CREATE VIRTUAL TABLE snippet USING fts4(title, body)'), 'Create table');

ok($oro->insert(snippet => { title => 'It is cold.', body => <<TEXT2 }), 'Insert');
During 30 Nov-1 Dec, 2-3oC drops.
Cool in the upper portion, minimum temperature 14-16oC
and cool elsewhere, minimum temperature 17-20oC.
Cold to very cold on mountaintops, minimum temperature 6-12oC.
Northeasterly winds 15-30 km/hr.
After that, temperature increases. Northeasterly winds 15-30 km/hr.
TEXT2

ok($snippet = $oro->snippet, 'Create snippet');

ok($result = $oro->select(
  snippet => [ [ $snippet => 'example' ] ] =>
    { body => { match => 'cold' } }), 'Select with snippet');

is(index($result->[0]->{example}, '<b>...</b>cool elsewhere, '), 0,
   'Snippet equal');

ok(index($result->[0]->{example}, 'minimum temperature 6<b>...</b>') > 0,
   'Snippet equal');

$snippet = $oro->snippet(
  start => '.oO(',
  end => ')',
  ellipsis => '.oOo.',
  token => 5
);

ok($result = $oro->select(
  text => [ [ $snippet => 'example' ] ] =>
    { text => { match => 'cold' } }), 'Select with snippet');

ok(index($result->[0]->{example}, '.oO(Cold)') > 0, 'Snippet equal');
ok(index($result->[0]->{example}, '.oO(cold)') > 0, 'Snippet equal');


1;

__END__
