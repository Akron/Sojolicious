#!/usr/bin/perl
$|++;

package Atom;
use lib '../lib';
use Mojo::Base 'Mojolicious::Plugin::XML::Base';

our $PREFIX = 'atom';
our $NAMESPACE = 'http://www.w3.org/2005/Atom';

# Add id
sub add_id {
  my $self = shift;
  my $id   = shift;
  return unless $id;
  my $element = $self->add('id', $id);
  $element->parent->attrs('xml:id' => $id);
  return $element;
};

package Fun;
use lib '../lib';
use Mojo::Base 'Mojolicious::Plugin::XML::Base';

our $NAMESPACE = 'http://sojolicio.us/ns/fun';
our $PREFIX = 'fun';

sub add_happy {
  my $self = shift;
  my $word = shift;

  my $cool = $self->add('-Cool');

  $cool->add('Happy',
	     {foo => 'bar'},
	     uc($word) . '!!! \o/ ' );
};

package main;
use lib '../lib';

use Test::More tests => 13;

my $fun_ns  = 'http://sojolicio.us/ns/fun';
my $atom_ns = 'http://www.w3.org/2005/Atom';

my $node = Fun->new('Fun');
my $text = $node->add('Text', 'Hello World!');

is($node->at(':root')->namespace, $fun_ns, 'Namespace');
is($text->namespace, $fun_ns, 'Namespace');

my $yeah = $node->add_happy('Yeah!');

is($yeah->namespace, $fun_ns, 'Namespace');
is($node->at('Cool')->namespace, $fun_ns, 'Namespace');

$node = Mojolicious::Plugin::XML::Base->new('object');

ok(!$node->at(':root')->namespace, 'Namespace');

$node->add_extension('Fun');
$yeah = $node->add_happy('Yeah!');


is($yeah->namespace, $fun_ns, 'Namespace');

$text = $node->add('Text', 'Hello World!');

ok(!$text->namespace, 'Namespace');

$text->add_extension('Atom');

my $id = $node->add_id('1138');

is($id->namespace, $atom_ns, 'Namespace');

ok(!$node->at('Cool')->namespace, 'Namespace');

$node = Fun->new('Fun');

$node->add_extension('Atom');

$yeah = $node->add_happy('Yeah!');

$id = $node->add_id('1138');

is($yeah->namespace, $fun_ns, 'Namespace');
is($node->at('Cool')->namespace, $fun_ns, 'Namespace');
is($id->namespace, $atom_ns, 'Namespace');
is($id->text, '1138', 'Content');
