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

sub follow {
    my $self = shift;
    my $user = $self->stash('poco_user');

    my $acct = shift;

    my $webfinger_xrd = $self->webfinger($acct);

    if ($webfinger_xrd) {
	my $doc = $self->new_ostatus_as;
	$doc->add_actor();
    };

    # 'after_ostatus_follow' hook (Für evtl. pubsub_publish
};

sub unfollow {
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
