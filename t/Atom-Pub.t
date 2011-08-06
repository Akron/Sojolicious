package Atom::TestController;
use Mojo::Base 'Mojolicious::Controller';
use Test::More;

my $poco_ns = 'http://www.w3.org/TR/2011/WD-contacts-api-20110616/';

sub get_feed {
  my $self = shift;
  my $feed = $self->new_atom('feed');
  my $bender = $feed->new_person(name => 'Bender');

  $feed->add_author($bender);

  my $entry = $feed->add_entry(id => '#7828zUUHuw2uhbjht' )->comment('Entry');
  $entry->add_author(name => 'Fry');

  $bender->add_ns('poco' => $poco_ns);
  $bender->add('poco:birthday' => '1/1/1970');

  $entry->add_contributor($bender);

  return $self->render(
      'format' => 'atom',
      'data' => $feed->to_pretty_xml
      );
};

sub delete_entry;
sub get_entry;
sub put_entry;

sub post_entry {
    my $c = shift;
    my $feed = shift;
    my $entry = $c->stash('plugin.atom');
    my $new_entry = $entry;
    my $location = '/huhuhu';

    # Success!

    my $headers = $c->res->headers;
    $headers->header('Location' => $location);
    $headers->header('Content-Location' => $location);

    $c->render(
	status => 201, # Created
	format => 'atom',
        data   => $new_entry->to_pretty_xml,
	);
};

package main;
use strict;
use warnings;

use Test::Mojo;
use Mojolicious::Lite;

use Test::More tests => 1;

use_ok('Mojolicious::Plugin::Atom::Pub');

__END__

# Shortcut
my $routes = $app->routes;
$routes->namespace('Atom');
$routes->route('/atom')->atom(controller => 'test_controller');

# FeedURI

$t->get_ok('/atom/FeedURI')
  ->status_is(200)
  ->content_type_is('application/atom+xml')
  ->text_is('feed author name' => 'Bender')
  ->text_is('entry id' => '#7828zUUHuw2uhbjht')
  ->text_is('entry author name' => 'Fry')
  ->text_is('entry contributor birthday' => '1/1/1970');

my $atom_dom = $t->ua->get('/atom/FeedURI')->res->dom;
is($atom_dom->at('feed entry contributor birthday')->namespace,
   $poco_ns, 'Namespace');
1;
