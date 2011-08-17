package Mojolicious::Plugin::PubSubHubbub;
use Mojo::Base 'Mojolicious::Plugin';
use strict;
use warnings;
use Mojo::ByteStream ('b');

has [qw/hub host/];
has 'secure' => 0;

our $global_param;
BEGIN {
    $global_param = {
	'Content-Type' =>
	    'application/x-www-form-urlencoded'
    };
};

# Register plugin
sub register {
    my ($plugin, $mojo, $param) = @_;

    if (exists $param->{host}) {
	$plugin->host( $param->{host} );
    } else {
	unless (exists $mojo->renderer->helpers->{'hostmeta'}) {
	    $plugin->host( $mojo->hostmeta('host') || 'localhost' );
	} else {
	    $plugin->host( 'localhost' );
	};
    };

    $plugin->secure( $param->{secure} );

    # Add 'pubsub' shortcut
    $mojo->routes->add_shortcut(
	'pubsub' => sub {
	    my ($route, $param) = @_;

	    return unless $param eq 'cb';
	    # or $param eq 'hub'
	    # Internal hub is currently not supported
	    
	    # Set endpoint if enabled
	    if ( $mojo->can('set_endpoint') ) {
		$mojo->set_endpoint(
		    'pubsub-'.$param => {
			secure => $plugin->secure,
			host   => $plugin->host,
			route  => $route });
	    };

	    # Add 'callback' route
	    if ($param eq 'cb') {
		$route->to(
		    cb => sub {
			my $c = shift;

			# Hook on verification
			if ($c->param('hub.mode')) {
			    $plugin->verify( $c );
			}
			
			# Hook on callback
			else {
			    my $ct = $c->req->headers->header('Content-Type');

			    # Is Atom or RSS feed
			    if ($ct =~ m{application\/(?:rss|atom)\+xml}) {
				$mojo->run_hook( 'on_pubsub_callback' =>
						 $c );
				return 1;
			    }

			    # Bad request
			    else {
				return $c->render(
				    'template'       => 'pubsub-endpoint',
				    'template_class' => __PACKAGE__,
				    'status'         => 400 # bad request
				    );
			    };
			};
		    });
	    }

	    # Add 'hub' route
	    # Not implemented yet
	    else {
		# $route->to(
		#    cb => sub {	$plugin->hub( @_ ) }
		#    );
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
	    return $plugin->change_subscription( shift,
						 mode => 'subscribe',
						 topic => shift,
						 @_);
	});
    
    # Add 'unsubscribe' helper
    $mojo->helper(
	'unsubscribe' => sub {
	    return $plugin->change_subscription( shift,
						 mode => 'unsubscribe',
						 topic => shift,
						 @_ );
	});
};

# Ping a hub for topics
sub publish {
    my $plugin = shift;
    my $c = shift;

    # Create post message
    my $post = 'hub.mode=publish';
    foreach ( @_ ) {
	$post .= '&hub.url='.b($c->url_for($_)
			         ->to_abs
                                 ->to_string)->url_escape;
    };

    # Temporary
    return $post;

    # Post to hub
    my $res = $c->ua
	->max_redirects(3)
	->post( $plugin->hub,
		$global_param,
		$post);

    # is 2xx, incl. 204 aka successful
    if ($res->is_status_class(200)) {
	return 1;
    };
    
    # Not successful
    return 0;
};

sub callback {
    my $self = shift;
    my $c = shift;

};

# Verify a changed subscription or automatically refresh
sub verify {
    my $plugin = shift;
    my $c = shift;

    # Not correct
    unless ($c->param('hub.mode') ||
	    $c->param('hub.topic') ||
	    $c->param('hub.challenge')) {
	return $c->render(
	    'template'       => 'pubsub-endpoint',
	    'template_class' => __PACKAGE__,
	    'status'         => 400 # bad request
	    );
    }
    
    # Correct
    else {
	my $challenge = $c->param('hub.challenge');
	# Not verified
	my $ok = 0;
	
	my %param;
	foreach (qw/mode
                    topic
                    verify
                    lease_seconds
                    verify_token/) {
	    $param{$_} = $c->param('hub.'.$_) if $c->param('hub.'.$_);
	};

	# Run hook to see, if verification is granted.
	$plugin->app->run_hook( 'on_pubsub_verification' =>
				$c, \%param, \$ok );

	if ($ok) {
	    return $c->render(
		'code'   => 200,
		'format' => 'text',
		'data'   => $challenge
		);
	};
    };
    
    # Not found
    return $c->render_not_found;
};

# subscribe or unsubscribe from a topic
sub change_subscription {
    my $plugin = shift;
    my $c = shift;
    my %param = @_;

    # No topic url given
    if (!exists $param{topic} ||
	$param{topic} !~ m{^https?://} ||
	!exists $param{hub} ||
	$param{hub} !~ m{^https?://} ) {
	return;
    };

    # lease seconds is no integer or not necessary
    if ( ( exists $param{lease_seconds} &&
	   $param{lease_seconds} =~ /^\d+$/ ) ||
	 # lease_seconds is not necessary for unsubscribe
	 $param{mode} eq 'unsubscribe') {

	delete $param{lease_seconds};
    };

    # Get callback endpoint
    # Works only if endpoints provided
    $param{'callback'} = $c->get_endpoint('pubsub-cb');


    $plugin->app->run_hook(
	'before_pubsub_'.$param{mode} => $c, \%param
	);

    # Render post string
    my $post = '';
    foreach ( qw/callback
                 mode
                 topic
                 verify
                 lease_seconds
                 secret
                 verify_token/ ) {
	if (exists $param{$_}) {
	    $post .= '&hub.'.$_.'='.b($param{$_})->url_escape;
	};
    };

    $post .= '&hub.verify='.$_.'sync' foreach ('a','');

    # Temporary
    return $post;

    # Send subscription change to hub
    my $res = $c->ua
	->max_redirects(3)
	# wrong! hub!
	->post($param{hub},
	       $global_param,
	       $post);
    # $ua->max_redirects(0);
    
    # is 2xx, incl. 204 aka successful
    return 1 if $res->is_status_class(200);
    
    # Not successful
    return 0;
};

1;

__DATA__
@@ layouts/pubsub.html.ep
<!doctype html>
<html>
  <head>
    <title><%= $title %></title>
  </head>
  <body>
    <h1><%= $title %></h1>
    <%== content %>
  </body>
</html>

@@ pubsub-endpoint.html.ep
% layout 'pubsub', title => 'PubSubHubbub Endpoint';
    <p>
      This is an endpoint for the
      <a href="http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html">PubSubHubbub protocol</a>
    </p>
    <p>
      Your request was bad.
    </p>


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

  # In Controllers:
  # Publish a feed
  $c->publish('https://sojolicio.us/blog.atom',
              'https://sojolicio.us/activity.atom');
  # Subscribe to a feed
  $c->subscribe( topic => 'https://sojolicio.us/feed.atom',
                 lease_seconds => 154354367 );
  # Unsubscribe from a feed
  $c->unsubscribe( topic => 'https://sojolicio.us/feed.atom');

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

  $ps->host('sojolicio.us');
  my $host = $ps->host;

The host for the PubSubHubbub enabled domain.

=head2 C<secure>

  $ps->secure(1);
  my $sec = $wf->secure;

Use C<http> or C<https>.

=head2 C<hub>

  $ps->hub('http://pubsubhubbub.appspot.com/');
  my $hub = $ps->hub;

The preferred hub. Currently local hubs are not implemented.

=head1 HELPERS

=head2 C<publish>

  # In Controllers
  $c->publish( 'my_feed',                       # named route
               '/feed.atom',                    # relative paths
               'https://sojolicio.us/feed.atom' # absolute uris
             ):

Publish a list of feeds.

=head2 C<subscribe>

  # In Controllers
  $c->subscribe('https://sojolicio.us/feed.atom' =>
                lease_seconds => 123456 );

Subscribe to a topic. Allowed parameters are 'lease_seconds',
'secret', and 'verify_token'.

=head2 C<unsubscribe>

  # In Controllers
  $c->unsubscribe('https://sojolicio.us/feed.atom');

Unsubscribe from a topic. Allowed parameters are 'secret' and
'verify_token'.

=head1 HOOKS

=head2 C<on_pubsub_callback>

This hook is released, when content is snd to the pubsub endpoint.
The parameters include ??? and the current Controllers object.

=head2 C<before_pubsub_subscribe>

This hook is released, before a subscription request is sent to a hub.
The parameters include ???, the current Controllers object, and the
parameters for subscription.

=head2 C<before_pubsub_unsubscribe>

This hook is released, before an unsubscription request is sent
to a hub. The parameters include ???, the current Controllers
object, and the parameters for unsubscription.

=head2 C<on_pubsub_verification>

This hook is released, when a verification is requested. The parameters
are ???, The current controller object, and a string reference to a
false value. If verification is granted, this value has to be set to true.

=head1 DEPENDENCIES

L<Mojolicious>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
