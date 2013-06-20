package Net::IMP::Remote::Sereal;

use strict;
use warnings;
use Net::IMP::Remote::Protocol;
use Net::IMP qw(:DEFAULT :log);
use Net::IMP::Debug;
use Sereal::Encoder;
use Sereal::Decoder;

my $wire_version = 0x00000001;

sub new {
    bless {
	encoder => Sereal::Encoder->new,
	decoder => Sereal::Decoder->new({ incremental => 1 }),
    }, shift;
}

# data type mapping int -> dualvar
# basic data types are added, we check for more additional types in 
# IMPRPC_GET_INTERFACE and IMPRPC_SET_INTERFACE
my %dt_i2d = (
    IMP_DATA_STREAM+0 => IMP_DATA_STREAM,
    IMP_DATA_PACKET+0 => IMP_DATA_PACKET,
);

# return type mapping int -> dualvar
my %rt_i2d = map { ( $_+0 => $_ ) } (
    IMP_PASS,
    IMP_PASS_PATTERN,
    IMP_PREPASS,
    IMP_DENY,
    IMP_DROP,
    IMP_TOSENDER,
    IMP_REPLACE,
    IMP_PAUSE,
    IMP_CONTINUE,
    IMP_LOG,
    IMP_PORT_OPEN,
    IMP_PORT_CLOSE,
    IMP_ACCTFIELD,
);

# log level mapping int -> dualvar
my %ll_i2d = map { ( $_+0 => $_ ) } (
    IMP_LOG_DEBUG,
    IMP_LOG_INFO,
    IMP_LOG_NOTICE,
    IMP_LOG_WARNING,
    IMP_LOG_ERR,
    IMP_LOG_CRIT,
    IMP_LOG_ALERT,
    IMP_LOG_EMERG,
);

# rpc type mapping int -> dualvar
my %rpc_i2d = map { ( $_+0 => $_ ) } (
    IMPRPC_GET_INTERFACE,
    IMPRPC_SET_INTERFACE,
    IMPRPC_NEW_ANALYZER,
    IMPRPC_DEL_ANALYZER,
    IMPRPC_DATA,
    IMPRPC_SET_VERSION,
    IMPRPC_EXCEPTION,
    IMPRPC_INTERFACE,
    IMPRPC_RESULT,
);

my %arg2buf = (
    IMPRPC_GET_INTERFACE+0 => sub {
	# @_ -> list< data_type_id, list<result_type_id> > provider_ifs
	my @rv;
	for my $if (@_) {
	    my ($dtype,$rtypes) = @$if;
	    if ( defined $dtype ) {
		$dt_i2d{ $dtype+0 } ||= $dtype;
		$dtype += 0
	    }
	    if ( $rtypes ) {
		push @rv, [ $dtype , [ map { $_+0 } @$rtypes ]];
	    } else {
		push @rv, [ $dtype ]
	    }
	}
	return @rv;
    },
    IMPRPC_SET_INTERFACE+0 => sub {
	# @_ ->  <data_type_id, list<result_type_id>> provider_if
	my ($dtype,$rtypes) = @{$_[0]};
	my @rt = map { $_+0 } @$rtypes;
	if ( ! defined $dtype ) {
	    return [ undef , \@rt ]
	} else {
	    $dt_i2d{ $dtype+0 } ||= $dtype;
	    return [ $dtype+0 , \@rt ]
	}
    },
    IMPRPC_DATA+0 => sub {
	# @_ -> analyzer_id, dir, offset, data_type_id, char data[]
	return (@_[0,1,2],$_[3]+0,$_[4]);
    },
    IMPRPC_RESULT+0 => sub {
	# @_ -> analyzer_id, result_type_id, ...
	my ($id,$rtype) = @_;
	if ( $rtype == IMP_LOG ) {
	    # id,type - dir,offset,len,level,msg
	    return ($id,$rtype+0,@_[2,3,4],$_[5]+0,$_[6]);
	} else {
	    return ($id,$rtype+0,@_[2..$#_]);
	}
    },
);
$arg2buf{ IMPRPC_INTERFACE+0 } = $arg2buf{ IMPRPC_GET_INTERFACE+0 };


my %buf2arg = (
    IMPRPC_GET_INTERFACE+0 => sub {
	# @_ -> list< data_type_id, list<result_type_id> > provider_ifs
	my @rv;
	for my $if (@_) {
	    my ($dtype,$rtypes) = @$if;
	    $dtype = $dt_i2d{$dtype} if defined $dtype;
	    if ( $rtypes ) {
		push @rv, [ $dtype, [ map { $rt_i2d{$_} } @$rtypes ]];
	    } else {
		push @rv, [ $dtype ]
	    }
	}
	return @rv;
    },
    IMPRPC_SET_INTERFACE+0 => sub {
	# @_ ->  <data_type_id, list<result_type_id>> provider_if
	my ($dtype,$rtypes) = @{$_[0]};
	my @rt = map { defined($_) ? $rt_i2d{$_} :undef } @$rtypes;
	return [ defined($dtype) ? $dt_i2d{$dtype} : undef , \@rt ]
    },
    IMPRPC_DATA+0 => sub {
	# @_ -> analyzer_id, dir, offset, data_type_id, char data[]
	return (@_[0,1,2],$dt_i2d{$_[3]},$_[4]);
    },
    IMPRPC_RESULT+0 => sub {
	# @_ -> analyzer_id, result_type_id, ...
	my ($id,$rtype) = @_;
	if ( $rtype == IMP_LOG ) {
	    # id,type - dir,offset,len,level,msg
	    return ($id,$rt_i2d{$rtype},@_[2,3,4],$ll_i2d{$_[5]},$_[6]);
	} else {
	    return ($id,$rt_i2d{$rtype},@_[2..$#_]);
	}
    },
);
$buf2arg{ IMPRPC_INTERFACE+0 } = $buf2arg{ IMPRPC_GET_INTERFACE+0 };



sub buf2rpc {
    my ($self,$rdata) = @_;
    decode:
    my $out = undef;
    eval { $self->{decoder}->decode( $$rdata, $out ) } or return;
    return if ! $out;
    if ( $out->[0] == IMPRPC_SET_VERSION ) {
	die "wrong version $out->[1], can do $wire_version only"
	    if $out->[1] != $wire_version;
	return if $$rdata eq '';
	goto decode;
    } 
    my ($op,@args) = @$out;
    $op = $rpc_i2d{$op};
    if ( my $sub = $buf2arg{$op+0} ) {
	#$DEBUG && debug("calling buf2arg for $op");
	@args = $sub->(@args);
    }
    return [$op,@args];
}

sub rpc2buf {
    my ($self,$rpc) = @_;
    my ($op,@args) = @$rpc;
    if ( my $sub = $arg2buf{$op+0} ) {
	#$DEBUG && debug("calling arg2buf for $op");
	@args = $sub->(@args);
    }
    $op += 0; # dualvar -> int
    $self->{encoder}->encode([$op,@args])
}

sub init { 
    my ($self,$side) = @_;
    return if $side == 0;
    $self->rpc2buf([IMPRPC_SET_VERSION,$wire_version]) 
}

1;
