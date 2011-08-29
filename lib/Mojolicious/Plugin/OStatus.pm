package Mojolicious::Plugin::OStatus;
use Mojo::Base 'Mojolicious::Plugin';

our $ostatus_ns;
BEGIN {
    $ostatus_ns = 'http://ostatus.org/schema/1.0/';
};

# Register plugin
sub register {
    my ($plugin, $mojo, $param) = @_;
    
    my %default = (
	'host' => $param->{'host'}     || 'localhost:3000',
	'secure' => $param->{'secure'} || 0
	);

    my $helpers = $mojo->renderer->helpers;

    foreach (qw/HostMeta
                Webfinger
                MagicSignatures
                Salmon
                PubSubHubbub
                PortableContacts/) {

	$param->{ $_ } = +{} unless exists $param->{ $_ };
	$mojo->plugin($_ => { %default, %{ $param->{ $_ } } } );
    };

    $mojo->plugin(
	'ActivityStreams' => {
	    %default,
	    extensions => ['Atom-Threading', 'OStatus'],
	    helper     => 'new_ostatus_as'
	});
};

1;

__END__

sub subscribe {
    my $self = shift;
    my $user = $self->stash('poco_user');

    # No actor given! err_str()?
    return unless $user;

    # User, Group, or Feed
    my $uri = shift;

    my $object;
    # direct feed
    if (index($uri, 'http') == 0) {
	# atom / xrd
	# html
	# $self->pubsub_subscribe();
    }

    # Webfinger
    elsif (index($uri,'@') >= 0) {
	my $wf_xrd = $self->webfinger( $uri );
    my $hub = $wf_xrd->get_link('hub');
    
    return unless $hub;

    $wf_xrd->get_link('http://schemas.google.com/g/2010#updates-from');

#    };

    return unless $object;

    my $doc = $self->new_ostatus_as;

    $doc->add_actor('...');
    $doc->add_verb('subscribe');
    $doc->add_object(type => 'person');

    # 'after_ostatus_follow' hook (Für evtl. pubsub_publish
};

sub unsubscribe {
    my $self = shift;
    my ($acct, $id);

    if ($_[0] =~ /^\d+$/) {
	$id = shift;
    } else {
	$acct = shift;
    };
};

package Mojolicious::Plugin::OStatus::Document;

sub register_as_extension {
    return qw/add_attention add_conversation/;
};
sub add_attention {
    my $self = shift;
    my $entry = shift;

    $entry->add_ns('ostatus' => $ostatus_ns);

    $entry->add_link(
	rel => 'ostatus:attention',
	href => shift
	);
};

sub add_conversation {
    my $self = shift;
    $entry->add_ns('ostatus' => $ostatus_ns);
    $entry->add_link(
	rel => 'ostatus:attention',
	href => shift
	);
};

1;
