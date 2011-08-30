package Mojolicious::Plugin::PortableContacts;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::PortableContacts::Response;

has 'host';
has 'secure' => 0;

# http://www.w3.org/TR/2011/WD-contacts-api-20110616/
# -> $c->poco_find(['emails','accounts'] => { filterBy => ...});

# my $user = $c->poco('acct:akron@sojolicio.us');
# print $user->get('emails')->where(type => 'private');
# print $user->get(['emails','accounts'])->where(type => 'private');


# my $response = $c->poco('/@me/@all', { filterBy    => '-webfinger',
# 	  			         filterOp    => 'equals',
#				         filterValue => 'acct:akron@sojolicio.us'});

# Set condition regex
our %CONDITIONS_RE;
BEGIN {
    our %CONDITIONS_RE = (
	'filterBy'     => qr/./,
	'filterOp'     => qr/^(?:equals|contains|startswith|present)$/,
	'filterValue'  => qr/./,
	'updatedSince' => qr/./,
	'sortBy'       => qr/./,
	'sortOrder'    => qr/^(?:a|de)scending$/,
	'startIndex'   => qr/^\d+$/,
	'count'        => qr/^\d+$/,
	'fields'       => qr/^(?:[a-zA-Z,\s]+|\@all)$/
	);
};

# Register Plugin
sub register {
    my ($plugin, $mojo, $param) = @_;

    # Load Host-Meta if not already loaded.
    # This automatically loads the 'XRD' and 'Util-Endpoint' plugin.
    unless (exists $mojo->renderer->helpers->{'hostmeta'}) {
	$mojo->plugin('HostMeta', {'host' => $param->{'host'} });
    };

    # Set host
    if (exists $param->{host}) {
	$plugin->host( $param->{host} );
    } else {
	$plugin->host( $mojo->hostmeta('host') || 'localhost' );
    };

    # Set secure
    $plugin->secure( $param->{secure} );

    # Add 'poco' shortcut
    $mojo->routes->add_shortcut(
	'poco' => sub {
	    my ($route, $param) = @_;

	    # Set endpoint
	    $route->endpoint(
		'poco' => {
		    host   => $plugin->host,
		    scheme => $plugin->secure ? 'https' : 'http'
		});



	    # Add Route to Hostmeta
	    my $poco = { rel  => 'http://portablecontacts.net/spec/1.0',
			 href => $mojo->endpoint('poco') };
	    my $link = $mojo->hostmeta->add('Link', $poco);
	    $link->comment('Portable Contacts');
	    $link->add('Title','Portable Contacts API Endpoint');


	    # Todo: Check OAuth2 and fill $c->stash->{'poco_user'}

	    # /@me/@all/
	    $route->route('/')->name('poco/@me/@all-1')->to( cb => \&me_all );
	    $route->route('/@me/@all')->name('poco/@me/@all-2')->to( cb => \&me_all );

	    # /@me/@all/{id}
	    $route->route('/@me/@all/:id')->name('poco/@me/@all/{id}')->to(
		cb => sub {
		    my $c = shift;
		    return $plugin->me_self_id($c,
					       $c->stash('id'),
					       $plugin->get_param($c) );
		});

	    # /@me/@self
	    $route->route('/@me/@self')->name('poco/@me/@self')->to( cb => \&me_self );
	    
	    return;
	});
    
    # Add 'poco' helper
    # Todo: also for update and insert
    $mojo->helper(
	'poco' => sub {
	    my $c = shift;

	    # Path for requests
	    my $path = '/@me/@all';
	    if ($_[0] && !ref($_[0])) {
		$path = shift;
	    };

	    # Params for request
	    my $param = ref($_[0]) ? shift : {};

	    # Init response object
	    my $response = {};
	    $mojo->plugins->run_hook('get_poco',
				     $plugin,
				     $c,
				     $path,
				     $param,
				     $response);
	    return $response;
	});

};

# Return response for /@me/@self
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

# Return response for /@me/@all/{id}
sub me_self_id {
    my $plugin = shift;
    my $c = shift;
    my $id = shift;
    my $param = shift;

    my $path = '/@me/@all/'.$id;

    # Init response hash
    my $response = {};
    $c->app->plugins->run_hook('get_poco',
			       $plugin,
			       $c,
			       $path,
			       $param,
			       $response);

    # Does the user exist?
    my $status = $response->{totalResults} == 0 ? 404 : 200;

    $response =
	Mojolicious::Plugin::PortableContacts::Response->new($response);

    # Return value RESTful
    return $c->respond_to(
	xml => sub { shift->render('status' => $status,
				   'format' => 'xml',
				   'data'   => $response->to_xml)},

	any => sub { shift->render('status' => $status,
				   'format' => 'json',
				   'data'   => $response->to_json) }
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

sub get_param {
    my $self = shift;
    my $c = shift;
    my %param = %{ $c->param };
    my %new_param;
    foreach my $cond (keys %CONDITIONS_RE) {
	if (exists $param{$cond}) {
	    # Valid
	    if ($param{$cond} =~ $CONDITIONS_RE{$cond}) {
		$new_param{$cond} = $param{$cond};
	    }
	    # Not valid
	    else {
		$c->app->log->debug('Not a valid PoCo parameter: '.
				    qq{"$cond": "$param{$cond}"});
	    };
	};
    };
    return \%new_param;
};

1;

__END__



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



sub parse {
    my $self = shift;
    # json or xml or hash_refxs
    my $object = shift;

    return $self = bless $object, ref($self);
};



__END__

sub get {
    my $self = shift;
    my $key = shift;

    # singular attribute
    if ($key =~ $SINGULAR_RE) {
	return $self->{$key};
    }

    # plural attribute
    elsif ($key =~ $PLURAL_RE) {
	my $plural = defined $self->{$key} ? $self->{$key} : [];
	return Mojolicious::Plugin::PortableContacts::User::Plural->new($plural);
    };

    warn('Unknown attribute');
    return;
};


package Mojolicious::Plugin::PortableContacts::User::Plural;
use strict;
use warnings;

sub new {
    my $class = ref($_[0]) ? ref(shift(@_)) : shift;
    my $self = shift || [];
    bless $self, $class;
};

sub where {
    my $self = shift;
    my %conditions = @_;
    my @array = @$self;

    while (my ($key, $value) = each %conditions) {
	@array = grep ($_->{$key} eq $value, @array);
    };

    return $self->new(\@array);
};


