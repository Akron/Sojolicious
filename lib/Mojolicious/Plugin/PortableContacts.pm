package Mojolicious::Plugin::PortableContacts;
use Mojolicious::Plugin::PortableContacts::Response;
use Mojo::Base 'Mojolicious::Plugin';
use strict;
use warnings;

has 'host';
has 'secure' => 0;

# my $user = $c->poco('acct:akron@sojolicio.us');
# print $user->get('emails')->where(type => 'private');
# http://www.w3.org/TR/2011/WD-contacts-api-20110616/

#my $user = $c->poco('/@me/@all', {filterBy    => '-webfinger',
#				  filterOp    => 'equals',
#				  filterValue => 'acct:akron@sojolicio.us'});

sub register {
    my ($plugin, $mojo, $param) = @_;

    # Load Host-Meta if not already loaded.
    # This automatically loads the 'XRD' plugin.
    unless (exists $mojo->renderer->helpers->{'hostmeta'}) {
	$mojo->plugin('HostMeta', {'host' => $param->{'host'} });
    };

    if (exists $param->{host}) {
	$plugin->host( $param->{host} );
    } else {
	$plugin->host( $mojo->hostmeta('host') || 'localhost' );
    };

    $plugin->secure( $param->{secure} );

    $mojo->routes->add_shortcut(
	'poco' => sub {
	    my $route = shift;
	    my $param = shift;

	    $route->endpoint('poco' => {
		host => $plugin->host,
		scheme => $plugin->secure ? 'https' : 'http'
			     });


	    my $poco = { rel  => 'http://portablecontacts.net/spec/1.0',
			 href => $mojo->endpoint('poco') };
    
	    # Add Route to Hostmeta
	    my $link = $mojo->hostmeta->add('Link', $poco);
	    $link->comment('Portable Contacts');
	    $link->add('Title','Portable Contacts API Endpoint');
	    
	    # Todo: Check OAuth2 and fill $c->stash->{'poco_user'}

	    # $route->set_endpoint('');

	    # Point the route to poco

	    # /@me/@all/
	    $route->name('poco/@me/@all-1')
		->to(
		cb => \&me_all
		);
	    $route->route('/@me/@all')->name('poco/@me/@all-2')
		->to(
		cb => \&me_all
		);

	    # /@me/@all/{id}
	    $route->route('/@me/@all/:id')->name('poco/@me/@all/{id}')
		->to(
		cb => sub {
		    my $c = shift;
		    return $plugin->me_self_id($c,
					       $c->stash('id'),
					       $c->param);
		});

	    # /@me/@self
	    $route->route('/@me/@self')->name('poco/@me/@self')
		->to(
		cb => \&me_self 
		);

	    return;
	});
	# 'formats' => 'm/^(?:xml|json)$/';

    $mojo->helper(
	'poco2' => sub {
	    my $c = shift;
	    my $path = '/@me/@all';
	    if ($_[0] && !ref($_[0])) {
		$path = shift;
	    };

	    my $param = ref($_[0]) ? shift : {};

	    my $response = {};
	    $mojo->plugins->run_hook('get_poco2',
					 $plugin,
					 $c,
					 $path,
					 $param,
					 $response);

#	    my @entry;
#	    foreach my $entry (@{$response->{entry}}) {
#		push(@entry,
#		     Mojolicious::Plugin::PortableContacts::User
#		     ->new($entry) );
#	    };
#	    $response->{entry} = \@entry;
		
	    return $response;

	    # Todo: return as hash of many users. Always.
# Structure:
#{
#  "startIndex": 10,
#  "itemsPerPage": 10,
#  "totalResults": 12,
#  "entry": [
#    {
#      "id": "123",
#      "displayName": "Minimal Contact"
#    },

# startIndex ... in DB!
#	    my $response = {
#		totalResults => @$user_array || '0'
#	    };

	    # Add entries
	});


    $mojo->helper(
	# TODO: Allow also for update and insert
	'poco' => sub {
	    my $c = shift;
	    my $type = $_[1] ? shift : 'id';
	    my $id = shift;
	    
	    my $user_hash = {};
	    $mojo->plugins->run_hook('get_poco',
				     $plugin,
				     $c,
				     $type,
				     $id,
				     $user_hash);

	    return unless exists $user_hash->{id};

	    my $user = Mojolicious::Plugin::PortableContacts::User
		->new($user_hash);
	    return $user;
	});
};

sub me_self {
    my $c = shift;

    my $poco = $c->stash('poco_user');

    unless ($poco) {
	my $acct = $c->parse_acct($c->stash('user'));
	$poco =
	    $c->stash->{'poco_user'} =
	    $c->poco('-webfinger' => $acct);
    };
    
    return $c->render_not_found unless $poco;
    
    my $success = $c->respond_to(
	json => { data => $poco->to_json},
	any  => { format => 'xml',
		  data => $poco->to_xml }
	);
    
    return $c->render_not_found unless $success;
    
    $c->rendered;
    return;
};

sub me_self_id {
    my $plugin = shift;
    my $c = shift;
    my $id = shift;
    my $param = shift;

    my $response = {};

    $c->app->plugins->run_hook('get_poco2',
			       $plugin,
			       $c,
			       '/@me/@all/'.$id,
			       $param,
			       $response);

    my $status = 200;
    if ($response->{totalResults} == 0) {
	# ID does not exist
	$status = 404;
    };

    $response =
	Mojolicious::Plugin::PortableContacts::Response->new($response);

    return $c->respond_to(
	xml => sub { shift->render(status => $status,
				   'format' => 'xml',
				   data => $response->to_xml)},
	any => sub { shift->render(status => $status,
				   'format' => 'json',
				   data => $response->to_json) }
	);

};

sub me_all {
    my $c = shift;


    my $poco_user = $c->stash->{poco_user};
# Temp:
#    my $poco_user = $c->poco_load($c->stash('user'));
#    hook!
#    unless ($poco_user) {
#
#    };

    my $contacts = $poco_user->contacts( %{ $c->param } );

    my $success = $c->respond_to(
	json => { data => $contacts->to_json },
	any  => { format => 'xml',
		  data => $contacts->to_pretty_xml }
	);

    return $c->render_not_found unless $success;

    $c->rendered;
    return;
};

1;

__END__
