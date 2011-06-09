package Mojolicious::Plugin::PubSubHubbub;
use Mojo::Base 'Mojolicious::Plugin';
use strict;
use warnings;
use Mojo::ByteStream ('b');

has qw/callback_url hub/;
has 'host';
has 'secure' => 0;

our $global_param;
BEGIN {
    $global_param = {
	'Content-Type' =>
	    'application/x-www-form-urlencoded'
    }
};

sub register {
    my ($plugin, $mojo, $param) = @_;

    # Add 'pubsub' shortcut
    $mojo->routes->add_shortcut(
	'pubsub' => sub {
	    my ($route, $param) = @_;

	    return unless $param =~ /^(?:hu|c)b$/;

	    $route->name('pubsub-'.$param);
	    
	    if ( exists $mojo->renderer->helpers->{webfinger} ) {
		my $url = $mojo->url_for( 'pubsub-'.$param )->to_string;

		$url =
		    $plugin->secure .
		    $plugin->host .
		    $url;

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
	'subscribe' => sub {
	    return $plugin->unsubscribe( @_ );
	});
};

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

    # is 2xx, incl. 204
    if ($res->is_status_class(200)) {
	return 1;
    };

    return 0;
};

sub subscribe {
    my $plugin = shift;
    my $c = shift;

    return $plugin->_change_subscription(
	$c, mode => 'subscribe', @_
	);
};

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

    my $post = 'hub.callback=' . b($self->callback_url)->url_escape;
    foreach (qw/mode topic verify
               lease_seconds secret verify_token/) {
	if (exists $param{$_}) {
	    $post .= '&hub.'.$_.'='.b($param{$_})->url_escape;
	};
    };

    return $post;

    # Send subscription change to hub
    my $ua = $c->ua;
    $ua->max_redirects(3);
    my $res = $ua->post($self->hub,
			$global_param,
			$post);
    $ua->max_redirects(3);

    # is 2xx, incl. 204
    if ($res->is_status_class(200)) {
	return 1;
    };

    return 0;

};

1;

__END__

# Im Feed: <link rel="self" ... />
#          <link rel="hub" ... />

