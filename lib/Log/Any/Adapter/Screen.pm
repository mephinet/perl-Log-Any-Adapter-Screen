package Log::Any::Adapter::Screen; # -*- notidy -*-

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Log::Any;
use Log::Any::Adapter::Util qw(make_method);
use parent qw(Log::Any::Adapter::Base);

use Data::Dumper;
use Term::ReadKey 'GetTerminalSize';
use Time::HiRes;

my $CODE_RESET = do { require Term::ANSIColor; Term::ANSIColor::color('reset') }; # PRECOMPUTE
my $DEFAULT_COLORS = do { require Term::ANSIColor; my $tmp = {trace=>'yellow', debug=>'', info=>'green',notice=>'green',warning=>'bold blue',error=>'magenta',critical=>'red',alert=>'red',emergency=>'red'}; for (keys %$tmp) { if ($tmp->{$_}) { $tmp->{$_} = Term::ANSIColor::color($tmp->{$_}) } }; $tmp }; # PRECOMPUTE
my $CODE_FAINT = do { require Term::ANSIColor; Term::ANSIColor::color('faint') }; # PRECOMPUTE

my $Time0;

my @logging_methods = Log::Any->logging_methods;
our %logging_levels;
for my $i (0..@logging_methods-1) {
    $logging_levels{$logging_methods[$i]} = $i;
}
# some common typos
$logging_levels{warn} = $logging_levels{warning};

sub _min_level {
    my $self = shift;

    return $ENV{LOG_LEVEL}
        if $ENV{LOG_LEVEL} && defined $logging_levels{$ENV{LOG_LEVEL}};
    return 'trace' if $ENV{TRACE};
    return 'debug' if $ENV{DEBUG};
    return 'info'  if $ENV{VERBOSE};
    return 'error' if $ENV{QUIET};
    $self->{default_level};
}

sub init {
    my ($self) = @_;
    $self->{default_level} //= 'warning';
    $self->{stderr}    //= 1;
    $self->{_fh} = $self->{stderr} ? \*STDERR : \*STDOUT;
    $self->{use_color} //= $ENV{COLOR} // (-t $self->{_fh});
    if ($self->{colors}) {
        require Term::ANSIColor;
        # convert color names to escape sequence
        my $orig = $self->{colors};
        $self->{colors} = {
            map {($_,($orig->{$_} ? Term::ANSIColor::color($orig->{$_}) : ''))}
                keys %$orig
            };
    } else {
        $self->{colors} = $DEFAULT_COLORS;
    }
    $self->{min_level} //= $self->_min_level;
    $Time0 //= Time::HiRes::time();
}

sub hook_before_log {
    return;
    #my ($self, $msg) = @_;
}

sub hook_after_log {
    my ($self, $msg) = @_;
    print { $self->{_fh} } "\n" unless $msg =~ /\n\z/;
}

sub structured {
    my ( $self, $level, $category, @args ) = @_;

    return
        if $logging_levels{$level} < $logging_levels{ $self->{min_level} };

    my $time        = Time::HiRes::time();
    my $color_start = $self->{use_color} ? $self->{colors}{$level} : '';
    my $color_end   = $self->{use_color} ? $CODE_RESET : '';
    my @msgs        = grep { !ref } @args;
    my $msg         = sprintf( '[%9.3fms] %s%9s ', ( $time - $Time0 ) * 1000, $color_start, uc $level);
    $msg .= join ' ', @msgs;

    my @data = grep {ref} @args;
    if (@data) {
        my $indent = ( ( GetTerminalSize( $self->{fh} ) )[0] // 80 ) / 3;
        my $d = Data::Dumper->new( \@data );
        $d->Terse(1)->Sortkeys(1)->Pad( ' ' x $indent )->Quotekeys(0)->Pair('=');
        my $visi_length = length($msg) - length($color_start);
        my $data_str =
            ( $visi_length < ( $indent - 1 ) )
            ? substr( $d->Dump(), $visi_length )
            : "\n" . $d->Dump();
        my $data_color_start = $self->{use_color} ? $CODE_FAINT : '';
        $msg .= $data_color_start . $data_str;
    }
    $msg .= $color_end;

    $self->hook_before_log($msg);
    print { $self->{_fh} } $msg;
    $self->hook_after_log($msg);
}

for my $method (Log::Any->detection_methods()) {
    my $level = $method; $level =~ s/^is_//;
    make_method(
        $method,
        sub {
            my $self = shift;
            $logging_levels{$level} >= $logging_levels{$self->{min_level}};
        }
    );
}

1;
# ABSTRACT: Send logs to screen, with colors and some other features

=for Pod::Coverage ^(init|hook_.+|structured)$

=head1 SYNOPSIS

 use Log::Any::Adapter;
 Log::Any::Adapter->set('Screen',
     # min_level => 'debug', # default is 'warning'
     # colors    => { trace => 'bold yellow on_gray', ... }, # customize colors
     # use_color => 1, # force color even when not interactive
     # stderr    => 0, # print to STDOUT instead of the default STDERR
 );


=head1 DESCRIPTION

This Log::Any adapter prints log messages to screen (STDERR/STDOUT). The
messages are colored according to level (unless coloring is turned off). It has
a few other features: allow setting level from some environment variables, add
prefix/timestamps.

Parameters:

=over 4

=item * min_level => STRING

Set logging level. Default is warning. If LOG_LEVEL environment variable is set,
it will be used instead. If TRACE environment variable is set to true, level
will be set to 'trace'. If DEBUG environment variable is set to true, level will
be set to 'debug'. If VERBOSE environment variable is set to true, level will be
set to 'info'.If QUIET environment variable is set to true, level will be set to
'error'.

=item * use_color => BOOL

Whether to use color or not. Default is true only when running interactively (-t
STDOUT returns true).

=item * colors => HASH

Customize colors. Hash keys are the logging methods, hash values are colors
supported by L<Term::ANSIColor>.

The default colors are:

 method/level                 color
 ------------                 -----
 trace                        yellow
 debug                        (none, terminal default)
 info, notice                 green
 warning                      bold blue
 error                        magenta
 critical, alert, emergency   red

=item * stderr => BOOL

Whether to print to STDERR, default is true. If set to 0, will print to STDOUT
instead.

=item * default_level => STR (default: warning)

If no level-setting environment variables are defined, will default to this
level.

=back


=head1 ENVIRONMENT

=head2 COLOR => bool

Can be set to 0 to explicitly disable colors. The default is to check for C<<-t
STDOUT>>.

=head2 LOG_LEVEL => str

=head2 QUIET => bool

=head2 VERBOSE => bool

=head2 DEBUG => bool

=head2 TRACE => bool

These environment variables can set the default for C<min_level>. See
documentation about C<min_level> for more details.


=head1 SEE ALSO

Originally inspired by L<Log::Log4perl::Appender::ScreenColoredLevel>. The old
name for this adapter is Log::Any::Adapter::ScreenColoredLevel but at some point
I figure using a shorter name is better for my fingers.

L<Log::Any>

L<Log::Log4perl::Appender::ScreenColoredLevel>

L<Term::ANSIColor>
