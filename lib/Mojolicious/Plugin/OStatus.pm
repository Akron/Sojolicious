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
                PortableContacts
                ActivityStreams/) {

	$param->{$_} = {} unless exists $param->{$_};
	$mojo->plugin($_, { %default, %{ $param->{$_} } } );

    };
};

1;

__END__

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
