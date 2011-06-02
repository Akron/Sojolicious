package Mojolicious::Plugin::MagicSignatures;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::MagicEnvelope;
use Mojolicious::Plugin::MagicKey;

# Register plugin
sub register {
    my ($plugin, $mojo) = @_;

    my $types = $mojo->types;
    $types->type('me-key'  => 'application/magic-key');
    $types->type('me-xml'  => 'application/magic-envelope+xml');
    $types->type('me-json' => 'application/magic-envelope+json');

    $mojo->helper(
	'magicenvelope' => sub {
	    return $plugin->magicenvelope(@_);
	});

    $mojo->helper(
	'magickey' => sub {
	    return $plugin->magickey(@_);
	});
};

# MagicEnvelope
sub magicenvelope {
    my $plugin = shift;
    shift; # Controller is not interesting
    # Possibly interesting for $c->push_to('http://...');
   
    # New me::instance object.
    my $me = Mojolicious::Plugin::MagicEnvelope->new( @_ );

    # MagicEnvelope can not be build
    if (!$me || !$me->data) {
	warn 'Unable to create magic envelope';
	return;
    };

    # Return me
    return $me;
};

# MagicKey
sub magickey {
    my $plugin = shift;
    shift;  # Controller is not interesting
    # Possibly interesting for $c->push_to('http://...');
   
    return Mojolicious::Plugin::MagicKey->new(@_);
};

1;
