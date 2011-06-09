#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 10;

use_ok('Mojolicious::Plugin::XML::Simple');

my $xml = Mojolicious::Plugin::XML::Simple->new;
my $subnode = $xml->add('Test', { foo => 'bar' });

is($xml->dom->at('Test')->attrs->{foo}, 'bar', 'Attribute request');

$subnode->comment('This is a Test.');
my $subsubnode = $subnode->add('SubTest',{ rel => 'simple'} );
$subsubnode->add('SubTest', {rel => 'hard'}, 'Huhu');

is($xml->dom->at('SubTest')->attrs('rel'), 'simple', 'Attribute');
is($xml->dom->at('SubTest[rel="hard"]')->text, 'Huhu', 'Text');
is($xml->dom->at('SubTest[rel="simple"]')->text, '', 'Text');
is($xml->dom->at('SubTest[rel="simple"]')->all_text, 'Huhu', 'All Text');


$xml = Mojolicious::Plugin::XML::Simple->new(<<'XML');
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xml>
  <Test foo="bar">
    <SubTest rel="simple">
      <SubTest rel="hard">Huhu</SubTest>
    </SubTest>
  </Test>
</xml>
XML

is($xml->dom->at('SubTest')->attrs('rel'), 'simple', 'Attribute');
is($xml->dom->at('SubTest[rel="hard"]')->text, 'Huhu', 'Text');
is($xml->dom->at('SubTest[rel="simple"]')->text, '', 'Text');
is($xml->dom->at('SubTest[rel="simple"]')->all_text, 'Huhu', 'All Text');

