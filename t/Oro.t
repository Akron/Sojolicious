#!/usr/bin/env perl
use Mojolicious::Lite;
use Test::More tests => 23;
use Test::Mojo;
use Data::Dumper;

$|++;

use lib 'lib';
use lib '../lib';
use_ok 'DBIx::Oro';

my $t = Test::Mojo->new;
my $app = $t->app;

my $db_file = ':memory:';

$app->plugin('Config' => {
  default => {
    Oro => {
      default => {
	file => $db_file,
	init => sub {
	  my $oro = shift;
	  $oro->do(
	    'CREATE TABLE Article (
               id     INTEGER PRIMARY KEY,
               titel  TEXT,
               inhalt TEXT
             )') or return -1;
	}
      }
    }
  }
});

$app->hook(
  on_Books_oro_init => sub {
    my $oro = shift;
    is($oro->file, ':memory:', 'Init 1');
  }
);

$app->hook(
  on_oro_init => sub {
    my $oro = shift;
    is($oro->file, ':memory:', 'Init 2');
  }
);


$app->plugin('Oro' => {
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

Mojo::IOLoop->start;

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

ok($c->oro->insert(Article => { titel => 'Headline1', inhalt => 'Text1'}), 'Insert');
my $article = $c->oro->table('Article');
ok($article->insert({ titel => 'Headline2', inhalt => 'Text2' }), 'Insert');
ok($article->insert({ titel => 'Headline3', inhalt => 'Text3' }), 'Insert');
ok($article->insert({ titel => 'Headline4', inhalt => 'Text4' }), 'Insert');

is($c->oro->load(Article => { titel => 'Headline2' })->{inhalt}, 'Text2', 'Load');
is($c->oro->load(Article => { titel => 'Headline3' })->{inhalt}, 'Text3', 'Load');
is($c->oro->load(Article => { titel => 'Headline4' })->{inhalt}, 'Text4', 'Load');
