use strict;
use warnings;

package Net::IMP::Remote::Client;
use base 'Net::IMP::Base';
use fields qw(id);
use Net::IMP;
use Net::IMP::Remote::Protocol;
use Scalar::Util 'weaken';
use Carp;

sub new_factory {
    my ($class,%args) = @_;
    my $self = $class->SUPER::new_factory(%args);

    weaken( my $wself = $self );
    $self->{factory_args}{conn}->nextop({
	IMPRPC_EXCEPTION+0 => [ \&exception, $wself ],
	IMPRPC_RESULT+0    => sub { 
	    my $id = shift;
	    my $obj = $wself->{factory_args}{conn}->get_analyzer($id);
	    $obj->run_callback(\@_) if ref $obj;
	},
    }, -1 );
    return $self;
}

sub get_interface {
    my ($self,@if) = @_;
    my @analyzer_if;
    if ( $self->{factory_args}{conn}->rpc(
	[ IMPRPC_GET_INTERFACE, @if ],
	{
	    IMPRPC_EXCEPTION+0 => [ \&exception, $self ],
	    IMPRPC_INTERFACE+0 => \@analyzer_if,
	}
    )) {
	return @analyzer_if;
    } else {
	return
    }
}

sub set_interface {
    my ($self,$if) = @_;
    $self->{factory_args}{conn}->rpc([ IMPRPC_SET_INTERFACE,$if ]);
    return $self;
}

sub new_analyzer {
    my ($self,%ctx) = @_;
    my $obj = $self->SUPER::new_analyzer(%ctx);
    my $conn = $self->{factory_args}{conn};
    weaken(my $wobj = $obj);
    my $id = $obj->{id} = $conn->add_analyzer($wobj);
    $conn->rpc([ IMPRPC_NEW_ANALYZER,$id,\%ctx ]);
    return $obj;
}

sub data {
    my ($self,$dir,$data,$offset,$type) = @_;
    $self->{factory_args}{conn}->rpc([ IMPRPC_DATA,
	$self->{id} || die("data called on factory not analyzer"),
	$dir,$offset,$type//IMP_DATA_STREAM,$data ]);
}

sub close {
    my $self = shift;
    my $id = $self->{id} or return;
    my $conn = $self->{factory_args}{conn} or return;
    $conn->del_analyzer($id);
    $conn->rpc([ IMPRPC_DEL_ANALYZER,$id ]);
    1;
}

sub DESTROY { goto &close }

sub exception {
    my ($self,$id,$msg) = @_;
    if ( $id ) {
	if ( my $obj = $self->{factory_args}{conn}->get_analyzer($id) ) {
	    warn "[$id] $msg\n";
	    $obj->close
	} else {
	    warn "[$id/unknown] $msg\n"
	}
    } else {
	die "[*] $msg\n";
    }
}



1;
__END__

