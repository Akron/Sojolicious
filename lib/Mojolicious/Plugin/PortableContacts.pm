package Mojolicious::Plugin::PortableContacts;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::PortableContacts::Response;

has 'host';
has 'secure' => 0;

# Default count parameter.
has 'count'  => 0; # unlimited

# Set condition regex
our (%CONDITIONS_RE, $poco_ns);
BEGIN {
    our %CONDITIONS_RE = (
	filterBy     => qr/./,
	filterOp     => qr/^(?:equals|contains|startswith|present)$/,
	filterValue  => qr/./,
	updatedSince => qr/./,
	sortBy       => qr/./,
	sortOrder    => qr/^(?:a|de)scending$/,
	startIndex   => qr/^\d+$/,
	count        => qr/^\d+$/,
	fields       => qr/^(?:[a-zA-Z,\s]+|\@all)$/
	);
    our $poco_ns = 'http://portablecontacts.net/spec/1.0';
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
	    my $poco = { rel  => $poco_ns,
			 href => $mojo->endpoint('poco') };
	    for ($mojo->hostmeta->add('Link', $poco)) {
		$_->comment('Portable Contacts');
		$_->add('Title','Portable Contacts API Endpoint');
	    };

	    # Todo: Check OAuth2 and fill $c->stash->{'poco_user_id'}

	    # /@me/@all/
	    my $me_all = $route->waypoint('/')->name('poco/@me/@all-1')->to(
		cb => sub {
		    $plugin->me_multiple( shift );
		});
	    $me_all->route('/@me/@all')->name('poco/@me/@all-2')->to;


	    # /@me/@all/{id}
	    $route->route('/@me/@all/:id')->name('poco/@me/@all/{id}')->to(
		cb => sub {
		    my $c = shift;
		    $c->stash('poco_user_id' => $c->stash('id'));
		    return $plugin->me_single($c);
		});


	    # /@me/@self
	    $route->route('/@me/@self')->name('poco/@me/@self')->to(
		cb => sub {
		    my $c = shift;
		    $c->stash('poco_user_id' => $c->stash('poco_me_id')); # ???
		    return $plugin->me_single($c);
		});
	    
	    return;
	});
    
    # Add 'poco' helper
    # Todo: also for update and insert
    $mojo->helper('poco' => sub { $plugin->get_poco( @_ ); } );
};

# Get PortableContacts
sub get_poco {
    my $plugin = shift;
    my $c = shift;
    
    # Init response object
    my $response = { entry => (@_ > 1 ? [] : +{} ) };

    # Return empty response if no parameter was set
    return _new_response($response) unless defined $_[0];

    # Accept id or param hashref
    my $param = (@_ > 1) ? { @_ } : { id => $_[0] };
    
    # Run 'get_poco' hook
    $c->app->plugins->run_hook('get_poco',
			       $plugin,
			       $c,
			       $param,
			       $response);
    return _new_response($response);
};

# Return response for /@me/@self or /@me/@all/{id}
sub me_single {
    my ($plugin, $c) = @_;

    my $id = $c->stash('poco_user_id');

    my $response = {entry => +{}};
    my $status = 404;

    if ($id) {

	# Clone parameters with values 
	my %param;
	foreach ($c->param) {
	    $param{$_} = $c->param($_) if $c->param($_);
	};

	# Get results
	$response = $plugin->get_poco( $c =>
				       $plugin->get_param(\%param),
				       id => $id
	    );
	$status = 200 if $response->totalResults;
    };
    
    # Render poco
    return $plugin->render_poco($c => _new_response($response),
				status => $status);
};

# Return response for /@me/@all
sub me_multiple {
    my ($plugin, $c) = @_;

    # Clone parameters with values 
    my %param;
    foreach ($c->param) {
	$param{$_} = $c->param($_) if $c->param($_);
    };
 
    # Get results
    my $response = $plugin->get_poco( $c =>
				      $plugin->get_param(\%param));

    # Render poco
    return $plugin->render_poco($c => $response);
};

# respond to poco
sub render_poco {
    my $plugin   = shift;
    my $c        = shift;
    my $response = shift;
    my %param    = @_;

    # Return value RESTful
    return $c->respond_to(
	xml => sub { shift->render('status' => $param{status} || 200,
				   'format' => 'xml',
				   'data'   => $response->to_xml) },

	any => sub { shift->render('status' => $param{status} || 200,
				   'format' => 'json',
				   'data'   => $response->to_json) }
	);
};

# Check for valid parameters
sub get_param {
    my $plugin = shift;
    my %param = %{ shift(@_) };

    my %new_param;
    foreach my $cond (keys %CONDITIONS_RE) {
	if (exists $param{$cond}) {

	    # Valid
	    if ($param{$cond} =~ $CONDITIONS_RE{$cond}) {
		$new_param{$cond} = $param{$cond};
	    }

	    # Not valid
	    else {
		$plugin->app->log->debug(
		    'Not a valid PoCo parameter: '.
		    qq{"$cond": "$param{$cond}"});
	    };
	};
    };
    
    # Set correct count parameter
    my $count = $plugin->count;
    if (exists $new_param{count}) {
	if ($count) {
	    if ($count > $new_param{count}) {
		$count =  delete $new_param{count};
	    } else {
		delete $new_param{count};
		delete $new_param{startIndex};
	    };
	} else {
	    $count = delete $new_param{count};
	};
    } else {
	delete $new_param{startIndex};
    };

    if ($count) {
	$new_param{count} = $count;
    };

    return %new_param;
};

# Private function for response objects
sub _new_response {
    if (ref($_[0]) eq
	'Mojolicious::Plugin::PortableContacts::Response') {
	return $_[0];
    } else {
	return Mojolicious::Plugin::PortableContacts::Response->new(@_);
    };
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::PortableContacts

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('PortableContacts');

  # Mojolicious::Lite
  plugin 'Portable::Contacts';

  my $response = $c->poco({ filterBy    => 'name.givenName',
                            filterOp    => 'startswith',
                            filterValue => 'Ak',
                            fields      => 'name, birthday'});

  print $response->entry->[0]->to_xml;

  return $c->render_poco($response);

=cut





# http://www.w3.org/TR/2011/WD-contacts-api-20110616/
# -> $c->poco_find(['emails','accounts'] => { filterBy => ...});

# my $user = $c->poco('acct:akron@sojolicio.us');
# print $user->get('emails')->where(type => 'private');
# print $user->get(['emails','accounts'])->where(type => 'private');


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


