use strict;
use warnings;

package Net::IMP::Remote;
use base 'Net::IMP::Remote::Client';
use Net::IMP::Remote::Connection;
use Net::IMP::Remote::Protocol;
use IO::Socket::INET;
use IO::Socket::UNIX;
use Net::IMP::Debug;
use Carp;

our $VERSION = '0.001';

my $INETCLASS = 'IO::Socket::INET';
BEGIN {
    for(qw(IO::Socket::IP IO::Socket::INET6)) {
	eval "require $_" or next;
	$INETCLASS = $_;
	last;
    }
}

sub validate_cfg {
    my ($class,%args) = @_;
    my @err;
    push @err,"no address given" if ! delete $args{addr};
    eval { Net::IMP::Remote::Protocol->load_implementation(delete $args{impl})}
	or push @err,$@;
    return (@err,$class->SUPER::validate_cfg(%args));
}

sub new_factory {
    my ($class,%args) = @_;
    my $ev = delete $args{eventlib} or croak(
	"data provider does not offer integration into its event loop with eventlib argument");
    my $addr = delete $args{addr} or croak("no addr given");
    my $fd = $addr =~m{/} 
	? IO::Socket::UNIX->new(Peer => $addr, Type => SOCK_STREAM) 
	: $INETCLASS->new($addr)
	or die "failed to connect to $addr: $!";
    $fd->blocking(0);
    debug("connected to $addr");
    my $conn = Net::IMP::Remote::Connection->new($fd,0,
	impl => delete $args{impl}, 
	eventlib => $ev
    );
    my $self =  $class->SUPER::new_factory(%args, conn => $conn, eventlib => $ev);
    return $self;
}


1;
__END__

=head1 NAME 

Net::IMP::Remote - connect to IMP plugins outside the process

=head1 SYNOPSIS

  perl imp-relay.pl ... -M Net::IMP::Remote=addr=imp-host:2000 ...

=head1 DESCRIPTION

L<Net::IMP::Remote> redirects the interaction with the IMP API to a server
process, which might be on the local or on a different machine. Current
implementation feature connection using UNIX domain sockets or TCP sockets.

The RPC functionality is described in L<Net::IMP::Remote::Protocol>.
L<Net::IMP::Remote::Connection> implements interactions using the defined RPCs
over a flexible wire protocol. The default wire implementation using the Sereal
library is done in L<Net::IMP::Remote::Sereal>.
L<Net::IMP::Remote::Client> and L<Net::IMP::Remote::Server> implement the
client and server side of the connection, while L<Net::IMP::Remote> finally
implements the usual IMP interface, so that this plugin can be used whereever
other IMP plugins can be used, although it's used best in data providers
offering an integration into their event loop.

=head2 Implementation and Overhead

Unlike other solutions like ICAP IMP tries to keep the overhead small.
A new connection to the IMP RPC server is done once, when the factory object is
created. Traffic for all analyzers created from the factory will be multiplexed
over the same connection, thus eliminating costly connection setup.
All RPC calls, except the initial get_interface after creating the factory
object, are asynchronous, because they don't need an immediate reply to
continue operation.

=head2 Integration Into Data Providers Event Loop

While it is possible to use L<Net::IMP::Remote> without an event loop it is
slower, because all read and write operation will block until they are done.
But the data provider might provide a simple event loop object within the
C<new_factory> call:

  my $factory = Net::IMP::Remote->new_factory(
    addr => 'host:port',
    eventlib => myEventLib->new
  );

The event lib object should implement the following simple interface

=over 4

=item ev->onread(fh,callback)

If callback is given it will set it up as a read handler, e.g. whenever the
file handle gets readable the callback will be called without arguments.
If callback is not given it will remove any existing callback, thus ignoring if
the file handle gets readable.

=item ev->onwrite(fh,callback)

Similar to C<onread>, but for write events

=item ev->timer(after,callback,[interval]) -> timer_obj

This will setup a timer, which will be called after C<after> seconds and call
C<callback>. If C<interval> is set it will reschedule the timer again and again
to be called every C<interval> seconds. 
Ths method returns an object C<timer_obj>. If this object gets destroyed the
timer will be canceled.

=back

=head1 TODO

See TODO file in distribution

=head1 SEE ALSO

L<Sereal::Encoder>
L<Sereal::Decoder>

=head1 AUTHOR

Steffen Ullrich
