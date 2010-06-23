use strict;
use warnings;
use POE;
use POE::Quickie;
use Test::More tests => 5;

POE::Session->create(
    package_states => [
        (__PACKAGE__) => [qw(
            _start
            stdout
            stderr
        )],
    ],
);

POE::Kernel->run;

sub _start {
    my $heap = $_[HEAP];

    $heap->{quickie} = POE::Quickie->new();
    $heap->{quickie}->run(
        Program     => sub { print "foo\n" },
        StdoutEvent => 'stdout',
        Context     => 'baz',
    );
}

sub stdout {
    my ($heap, $output, $pid, $context) = @_[HEAP, ARG0..ARG2];
    is($output, 'foo', 'Got stdout');
    is($context, 'baz', 'Got context');
    my $programs = $heap->{quickie}->programs();
    is($programs->{$pid}, 'baz', '$quickie->programs() works');
    
    $heap->{quickie}->run(
        Program     => sub { warn "bar\n" },
        StderrEvent => 'stderr',
        Context     => 'quux',
    );
}

sub stderr {
    my ($heap, $error, $context) = @_[HEAP, ARG0, ARG2];
    is($error, 'bar', 'Got stderr');
    is($context, 'quux', 'Got context');
}
