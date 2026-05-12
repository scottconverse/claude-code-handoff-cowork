#!/usr/bin/env perl
# handoff_turn_format.pl — drop-in replacement for the jq pipeline in
# handoff_turn_append.sh. Reads transcript JSONL lines [start..end] (1-based,
# inclusive), emits a formatted markdown turn block on STDOUT.
#
# Usage: perl handoff_turn_format.pl <transcript_path> <start_line> <end_line>
#
# Uses only JSON::PP (Perl core since 5.14) — no CPAN install needed on any
# platform Claude Code targets (MSYS, macOS, Linux).

use strict;
use warnings;
use JSON::PP;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my ($path, $start, $end) = @ARGV;
die "usage: $0 <transcript_path> <start_line> <end_line>\n"
    unless defined $path && defined $start && defined $end;

open(my $fh, '<:encoding(UTF-8)', $path) or exit 0;

my $i = 0;
while (my $line = <$fh>) {
    $i++;
    next if $i < $start;
    last if $i > $end;

    chomp $line;
    next unless length $line;

    my $obj = eval { decode_json($line) };
    next if $@ || !$obj;

    my $type = $obj->{type} // '';
    my $content = $obj->{message}{content};

    if ($type eq 'user') {
        emit_user($content);
    } elsif ($type eq 'assistant') {
        emit_assistant($content);
    }
}

close $fh;
exit 0;

# -----------------------------------------------------------------------------

sub emit_user {
    my ($content) = @_;
    return unless defined $content;

    if (!ref $content) {
        # string form
        my $t = strip_noise($content);
        print "**User:**\n\n$t\n\n" if $t =~ /\S/;
        return;
    }

    if (ref $content eq 'ARRAY') {
        # Collect all text-type entries, strip noise, emit if non-empty.
        my @user_text_parts;
        for my $c (@$content) {
            next unless ref $c eq 'HASH';
            next unless ($c->{type} // '') eq 'text';
            push @user_text_parts, strip_noise($c->{text} // '');
        }
        my $user_text = join("\n", grep { /\S/ } @user_text_parts);
        print "**User:**\n\n$user_text\n\n" if $user_text =~ /\S/;

        # Tool results — keep, truncate to 800 chars, do NOT strip noise tags
        # (tool output is content, not Claude Code injection).
        for my $c (@$content) {
            next unless ref $c eq 'HASH';
            next unless ($c->{type} // '') eq 'tool_result';
            my $tid = $c->{tool_use_id} // '?';
            my $body = $c->{content};
            my $bs;
            if (!ref $body) {
                $bs = $body // '';
            } elsif (ref $body eq 'ARRAY') {
                $bs = join("\n",
                    map  { $_->{text} // '' }
                    grep { ref $_ eq 'HASH' && ($_->{type} // '') eq 'text' }
                    @$body);
            } else {
                $bs = eval { encode_json($body) } // '';
            }
            $bs = substr($bs, 0, 800);
            print "**Tool result** (`$tid`):\n\n```\n$bs\n```\n\n";
        }
    }
}

sub emit_assistant {
    my ($content) = @_;
    return unless ref $content eq 'ARRAY';

    my @texts;
    for my $c (@$content) {
        next unless ref $c eq 'HASH';
        next unless ($c->{type} // '') eq 'text';
        push @texts, ($c->{text} // '');
    }
    my $at = join("\n", @texts);
    print "**Assistant:**\n\n$at\n\n" if $at =~ /\S/;

    my @calls;
    for my $c (@$content) {
        next unless ref $c eq 'HASH';
        next unless ($c->{type} // '') eq 'tool_use';
        my $name = $c->{name} // '?';
        my $inp = eval { encode_json($c->{input} // {}) } // '{}';
        $inp =~ s/\n/ /g;
        $inp = substr($inp, 0, 300);
        push @calls, "- `$name` \x{2014} $inp";
    }
    if (@calls) {
        print "**Tool calls:**\n\n" . join("\n", @calls) . "\n\n";
    }
}

sub strip_noise {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s{<system-reminder>.*?</system-reminder>\s*}{}gs;
    $s =~ s{<command-name>.*?</command-name>\s*}{}gs;
    $s =~ s{<command-message>.*?</command-message>\s*}{}gs;
    $s =~ s{<command-args>.*?</command-args>\s*}{}gs;
    $s =~ s{<local-command-stdout>.*?</local-command-stdout>\s*}{}gs;
    $s =~ s{\n{3,}}{\n\n}gs;
    return $s;
}
