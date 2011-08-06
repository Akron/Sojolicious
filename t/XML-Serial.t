#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 21;

use_ok('Mojolicious::Plugin::XML::Serial');

my $xml = Mojolicious::Plugin::XML::Serial->new('test');
my $subnode = $xml->add('Test', { foo => 'bar' });

is($xml->at('Test')->attrs->{foo}, 'bar', 'Attribute request');

$subnode->comment('This is a Test.');
my $subsubnode = $subnode->add('SubTest',{ rel => 'simple'} );
$subsubnode->add('SubTest', {rel => 'hard'}, 'Huhu');

is($xml->at('SubTest')->attrs('rel'), 'simple', 'Attribute');
is($xml->at('SubTest[rel="hard"]')->text, 'Huhu', 'Text');
is($xml->at('SubTest[rel="simple"]')->text, '', 'Text');
is($xml->at('SubTest[rel="simple"]')->all_text, 'Huhu', 'All Text');

$xml = Mojolicious::Plugin::XML::Serial->new(<<'XML');
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xml>
  <Test foo="bar">
    <SubTest rel="simple">
      <SubTest rel="hard">Huhu</SubTest>
    </SubTest>
  </Test>
</xml>
XML

is($xml->at('SubTest')->attrs('rel'), 'simple', 'Attribute');
is($xml->at('SubTest[rel="hard"]')->text, 'Huhu', 'Text');
is($xml->at('SubTest[rel="simple"]')->text, '', 'Text');
is($xml->at('SubTest[rel="simple"]')->all_text, 'Huhu', 'All Text');

$xml->add('ParaTest', { rel => "para" }, 'Para');

is($xml->at('ParaTest')->attrs('rel'), 'para', 'Attribute');
is($xml->at('ParaTest[rel="para"]')->text, 'Para', 'Text');

$xml = Mojolicious::Plugin::XML::Serial->new('html');
my $body = $xml->add('body', {color => '#ffffff' })->comment('body');
$body->add('h1', 'Headline');
$body->add('p', 'Paragraph');

is($xml->at('body')->attrs('color'), '#ffffff', 'Attribute');
is($xml->at('h1')->text, 'Headline', 'Text');
is($xml->at('p')->text, 'Paragraph', 'Text');
is($xml->at('body')->all_text, 'Headline Paragraph', 'Text');

my $new_para = Mojolicious::Plugin::XML::Serial->new('p', { foo => 'bar' }, 'Paragraph2');

$xml->at('body')->add($new_para);
is($xml->at('body p:nth-of-type(2)')->text, 'Paragraph2', 'Text');


# Namespace declarations
my $my_ns = 'http://example.org/ns/my-1.0';

my $new_para_2 = Mojolicious::Plugin::XML::Serial->new('p', { this => 'test'});
$new_para_2->add_ns('my' => $my_ns);

$new_para_2->add('my:strong', {check => 'this'}, 'Works!' );

is($new_para_2->at('strong')->namespace, $my_ns, 'Namespace');
is($new_para_2->at('*')->attrs('xmlns:my'), $my_ns, 'Namespace-Declaration');

$xml->add($new_para_2);

is($xml->at('strong')->namespace, $my_ns, 'Namespace');
is($xml->at('*')->attrs('xmlns:my'), $my_ns, 'Namespace-Declaration');
