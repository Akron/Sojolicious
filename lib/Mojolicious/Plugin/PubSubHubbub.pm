package Mojolicious::Plugin::PubSubHubbub;
use Mojo::Base 'Mojolicious::Plugin';
use strict;
use warnings;
use Mojo::ByteStream ('b');

has qw/hub/;
has 'host';
has 'secure' => 0;

# global static parameter
our $global_param;
BEGIN {
    $global_param = {
	'Content-Type' =>
	    'application/x-www-form-urlencoded'
    }
};

# Register plugin
sub register {
    my ($plugin, $mojo, $param) = @_;

    # Add 'pubsub' shortcut
    $mojo->routes->add_shortcut(
	'pubsub' => sub {
	    my ($route, $param) = @_;

	    return unless $param eq 'cb';

	    # or $param eq 'hub'
	    # Internal hub is currently not supported
	    
	    # Set endpoint if enabled
	    if ( exists $mojo->renderer->helpers->{endpoint} ) {
		$mojo->endpoint(
		    'pubsub-'.$param =>
		    $plugin->secure,
		    $plugin->domain,
		    $route);
	    };

	    # Add 'callback' route
	    if ($param eq 'cb') {
		$route->to(
		    cb => sub {
			$plugin->callback( @_ );
		    });
	    }

	    # Add 'hub' route
	    else {
		$route->to(
		    cb => sub {
			$plugin->hub( @_ );
		    });
	    };

	});
    
    # Add 'publish' helper
    $mojo->helper(
	'publish' => sub {
	    return $plugin->publish( @_ );
	});
    
    # Add 'subscribe' helper
    $mojo->helper(
	'subscribe' => sub {
	    return $plugin->subscribe( @_ );
	});
    
    # Add 'unsubscribe' helper
    $mojo->helper(
	'unsubscribe' => sub {
	    return $plugin->unsubscribe( @_ );
	});
};

# Ping a hub for topics
sub publish {
    my $plugin = shift;
    my $c = shift;

    my $post = 'hub.mode=publish';
    foreach (@_) {
	$post .= '&hub.url='.b($_)->url_escape;
    };
    return $post;

    # Post to hub
    my $ua = $c->ua;
    $ua->max_redirects(3);
    my $res = $ua->post($plugin->hub,
			$global_param,
			$post);
    $ua->max_redirects(0);

    # is 2xx, incl. 204 aka successful
    if ($res->is_status_class(200)) {
	return 1;
    };
    
    # Not successful
    return 0;
};

# Subscribe to a topic
sub subscribe {
    my $plugin = shift;
    my $c = shift;

    return $plugin->_change_subscription(
	$c, mode => 'subscribe', @_
	);
};

# Unsubscribe from a topic
sub unsubscribe {
    my $plugin = shift;
    my $c = shift;

    return $self->_change_subscription(
	$c, mode => 'unsubscribe', @_
	);
};

sub callback {
    my $self = shift;
    my $c = shift;
};

sub hub {
    my $self = shift;
    my $c = shift;
};

sub _change_subscription {
    my $self = shift;
    my $c = shift;
    my %param = @_;

    if (!exists $param{topic} || $param{topic} !~ m{^https?://}) {
	return;
    };

    if (exists $param{lease_seconds} &&
	$param{lease_seconds} =~ /^\d+$/) {
	delete $param{lease_seconds} ;
    };

    $param{verify} = 'async';  # Sowohl sync als auch async.

    my $post = 'hub.callback=' . b($c->endpoint('pubsub-cb'))->url_escape;

    foreach (qw/mode topic verify
               lease_seconds secret verify_token/) {
	if (exists $param{$_}) {
	    $post .= '&hub.'.$_.'='.b($param{$_})->url_escape;
	};
    };

    # Send subscription change to hub
    my $ua = $c->ua;
    $ua->max_redirects(3);
    my $res = $ua->post($self->hub,
			$global_param,
			$post);
    $ua->max_redirects(3);

    # is 2xx, incl. 204 aka successful
    if ($res->is_status_class(200)) {
	return 1;
    };

    # Not successful
    return 0;

};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::PubSubHubbub

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('pub_sub_hubbub',
              { hub => 'https://hub.example.org/' }
              );

  my $r = $app->routes;
  $r->route('/:user/callback_url')->pubsub('cb')


  # Mojolicious::Lite
  plugin 'pub_sub_hubbub' => { hub => 'https://hub.example.org' };

  my $ps = any '/:user/callback_url';
  $ps->pubsub('cb);


=head1 DESCRIPTION

L<Mojolicious::Plugin::PubSubHubbub> is a plugin to support 
PubSubHubbub Webhooks
(see L<Specification|http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html>).

=head1 ATTRIBUTES

=head2 C<host>

  $wf->host('sojolicio.us');
  my $host = $wf->host;

The host for the webfinger domain.

=head2 C<secure>

  $wf->secure(1);
  my $sec = $wf->secure;

Use C<http> or C<https>.

=head2 C<hub>

=head1 HELPERS

=head2 C<publish>
=head2 C<subscribe>
=head2 C<unsubscribe>

=head1 DEPENDENCIES

L<Mojolicious>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
