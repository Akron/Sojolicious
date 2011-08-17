package Mojolicious::Plugin::PortableContacts;
use Mojo::Base 'Mojolicious::Plugin';
use strict;
use warnings;

has 'host';
has 'secure' => 0;

# my $user = $c->poco('acct:akron@sojolicio.us');
# print $user->get('emails')->where(type => 'private');
# http://www.w3.org/TR/2011/WD-contacts-api-20110616/

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
	    
	    my $poco = { rel  => 'http://portablecontacts.net/spec/1.0',
			 href => 'hmmm' };
    
	    # Add Route to Hostmeta
	    my $link = $mojo->hostmeta->add('Link', $poco);
	    $link->comment('Portable Contacts');
	    $link->add('Title','Portable Contacts Endpoint');
	    

	    # Todo: Check OAuth2 and fill $c->stash->{'poco_user'}

	    # Point the route to poco
	    $route->to(	cb => sub {} );

	    my $me = $route->route('/@me');

	    # /@me/@all == /
	    my $all = $me->waypoint('/@all')->to(
		cb => sub {
		    my $c = shift;
		    my $poco_user = $c->stash->{poco_user};
		    my $contacts = $poco_user->contacts( %{ $c->param } );
		    if ($c->param('format') eq 'json') {
			$contacts->to_json;
		    } else {
			$contacts->to_pretty_xml;
		    };
		});

	    # /@me/@all/{id}
	    $all->route('/:id')->to(cb => sub {});

	    # /@me/@self
	    $me->route('/@self')->to(
		cb => sub {
		    my $c = shift;
		    if (!$c->stash('poco_user')) {
			$c->stash->{'poco_user'} = $c->poco($c->stash->{user});
		    };
		});

	}

	);
	# 'formats' => 'm/^(?:xml|json)$/';


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

package Mojolicious::Plugin::PortableContacts::User;
use strict;
use warnings;
use Mojo::JSON;
use Mojolicious::Plugin::XML::Serial;

our ($SINGULAR_RE, $PLURAL_RE, $VALID_RE);
BEGIN {
    our $SINGULAR_RE = qr/(?:id|
                             (?:preferred_user|nick|display_)?name|
                             published|
                             updated|
                             birthday|
                             anniversary|
                             gender|
                             note|
                             utc_offset|
                             connected)$/x;
    our $PLURAL_RE = qr/^(?:email|
                            url|
                            phone_number|
                            im|
                            photo|
                            tag|
                            relationship|
                            organization|
                            addresse|
                            account)s$/x;
    our $VALID_RE = qr(^$SINGULAR_RE|$PLURAL_RE$);
};

sub new {
    my $class = shift;
    my $self = shift;
    bless $self, $class;
};

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

sub connections {
    my $self = shift;
    my %conditions = @_;
    my %cond = (
	'filterBy' => '',
	'filterOp' => 'm/^(?:equals|contains|startswith|present)$/',
	'filterValue' => '',
	'updatedSince' => '',
	'sortBy' => '',
	'sortOrder' => 'm/^(?:a|de)scending$/',
	'startIndex' => 'm/^\d+$/',
	'count' => 'm/^\d+$/',
	'fields' => 'm/^(?:[a-zA-Z,\s]+|\@all)$/',
	);
};

sub _node {
    my $self = shift;

    my $entry = Mojolicious::Plugin::XML::Serial->new('entry');

    foreach my $key (keys %$self) {

	# Normal value
	if (!ref $self->{$key} && $key =~ $SINGULAR_RE) {
	    $entry->add($key, $self->{$key});
	}

	else {
	    if (ref($self->{$key}) eq 'HASH'  && $key =~ $SINGULAR_RE) {
		my $node = $entry->add($key);
		while (my ($sub_key, $sub_value) = each (%{$self->{$key}})) {
		    $node->add($sub_key, $sub_value);
		};
	    }
	    elsif ($key =~ $PLURAL_RE) {
		foreach my $sub_node (@{$self->{$key}}) {
		    if ((ref $sub_node) eq 'HASH') {
			my $node = $entry->add($key);
			while (my ($sub_key, $sub_value) = each (%{$sub_node})) {
			    $node->add($sub_key, $sub_value);
			};
		    }
		    else {
			my $node = $entry->add($key, $sub_node);
		    };
		};
	    };
	};
    };

    return $entry;
};

sub to_xml {
    my $self = shift;
    return $self->_node->to_pretty_xml;
};

# Return as JSON string
sub to_json {
    # Only allow fine first values
    my %hash;
    foreach my $key (keys %{ $_[0] }) {
	if ($key =~ $VALID_RE) {
	    $hash{$key} = $_[0]->{$key};
	};
    };

    return Mojo::JSON->new->encode( \%hash );
};

sub parse {
    my $self = shift;
    # json or xml or hash_refxs
    my $object = shift;

    return $self = bless $object, ref($self);
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


__END__
