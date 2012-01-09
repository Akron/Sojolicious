use Test::More tests => 95;
use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';
use strict;
use warnings;

$|++;

use lib '../lib';
use Test::Mojo;
use Mojolicious::Lite;

my $t = Test::Mojo->new;
my $app = $t->app;

my $db_file = tmpnam();

END {
  unlink $db_file;
};

$app->plugin('Oro' => {
  'Books' => {
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

