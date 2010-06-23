use strict;
use warnings;
use POE;
use POE::Quickie;
use Test::More;

plan skip_all => 'This test needs POE >1.289' if $POE::VERSION le '1.289';
plan tests => 1;

POE::Session->create(
    package_states => [
        (__PACKAGE__) => [qw(
            _start
            exit
        )],
    ],
);

POE::Kernel->run;

sub _start {
    my $heap = $_[HEAP];

    $heap->{quickie} = POE::Quickie->new();
    $heap->{quickie}->run(
        Program     => sub { die },
        ExitEvent   => 'exit',
        StderrEvent => undef,
    );
}

sub exit {
    my ($heap, $status) = @_[HEAP, ARG0];
    isnt(($status >> 8), 0, 'Got exit status');
}
