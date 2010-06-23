use strict;
use warnings;
use POE;
use POE::Quickie;
use Test::More tests => 8;
use Capture::Tiny qw(capture);

POE::Session->create(
    package_states => [
        (__PACKAGE__) => [qw(
            _start
        )],
    ],
);

POE::Kernel->run;

sub _start {
    my $heap = $_[HEAP];

    my $before = time;
    my ($stdout, $stderr, $status) = quickie(sub { sleep 3; print "foo\n" });
    is(($status >> 8), 0, 'Correct exit status');
    is($stdout, "foo\n", 'Got stdout');
    my $after = time;
    cmp_ok($after - $before, '>=', 2, 'The program runs');

    my ($merged) = quickie_merged(sub { warn "foo\n"; print "bar\n" });
    is($merged, "foo\nbar\n", 'Got merged output');

    ($stdout, $stderr) = capture {
        quickie_tee(sub { print "stdout\n"; warn "stderr\n"});
    };

    is($stdout, "stdout\n", 'Got teed stdout');
    is($stderr, "stderr\n", 'Got teed stderr');


    ($stdout, $stderr) = capture {
        quickie_tee_merged(sub { warn "stderr\n"; print "stdout\n" });
    };

    is($stdout, "stderr\nstdout\n", 'Got tee merged stdout');
    is($stderr, '', 'Got tee merged stderr');
}
