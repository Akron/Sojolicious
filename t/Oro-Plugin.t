#!/usr/bin/env perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Test::More tests => 13;

use Test::Mojo;
use Mojolicious::Lite;

use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';

my $t = Test::Mojo->new;
my $app = $t->app;

my $db_file = tmpnam();

END {
  unlink $db_file;
};

$app->plugin('oro' => {
  Books => {
    file => $db_file,
    init => sub {
      my $oro = shift;
      $oro->do('CREATE TABLE Content (
                  id      INTEGER PRIMARY KEY,
                  title   TEXT,
                  content TEXT
                )') or return -1;
    }
  }
});

my $c = Mojolicious::Controller->new;
$c->app($app);

my $books = $c->oro('Books');
ok($books, 'Oro handle');

if ($books->created) {
  ok($books->txn(
    sub {
      my $oro = shift;
      $oro->do('CREATE TABLE Author (
                  id    INTEGER PRIMARY KEY,
                  name  TEXT,
                  age   TEXT
                )') or return -1;
    }
  ), 'Transaction');
};


ok($c->oro('Books')->insert(Author => { name => 'Akron', age => 24 }), 'Insert');
ok($c->oro(Books => 'Author')->insert( { name => 'Peter', age => 26 }), 'Insert');

is($c->oro(Books => 'Author')->count, 2, 'Count');
is($c->oro('Books')->count('Author'), 2, 'Count');

ok($c->oro('Books')->insert(Content => { title => 'Misery' }), 'Insert');
ok($c->oro(Books => 'Content')->insert({ title => 'She' }), 'Insert');
ok($c->oro(Books => 'Content')->insert({ title => 'It' }), 'Insert');

is($c->oro(Books => 'Content')->count, 3, 'Count');
is($c->oro('Books')->count('Content'), 3, 'Count');

is($c->oro(Books => 'Author')->count, 2, 'Count');
is($c->oro('Books')->count('Author'), 2, 'Count');
