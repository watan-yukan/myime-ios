#!/usr/bin/perl
# 把 McBopomofo（MIT）的 phrase.occ 轉成 MyIME 的內建詞庫 Shared/Lexicon/lexicon.txt（FR-S02）。
#
# 用法：perl Tools/build_lexicon.pl phrase.occ > Shared/Lexicon/lexicon.txt
# 來源：https://github.com/openvanilla/McBopomofo/blob/master/Source/Data/phrase.occ
#
# 輸出格式：每行「詞<TAB>次數」，只留 2～4 個中文字、次數 >= 1 的詞，依 Unicode 排序
# （同一個開頭字的詞會連在一起，鍵盤端依開頭字建索引，只讀需要的那一段）。
use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));  # 也套用到 <> 讀的檔案
binmode STDOUT, ':encoding(UTF-8)';

my %count;
while (my $line = <>) {
    $line =~ s/\r?\n$//;
    my ($phrase, $occ) = split /\s+/, $line;
    next unless defined $occ && $occ =~ /^\d+$/ && $occ >= 1;
    next unless $phrase =~ /^[\x{3400}-\x{4DBF}\x{4E00}-\x{9FFF}\x{F900}-\x{FAFF}\x{20000}-\x{2FA1F}]{2,4}$/;
    $count{$phrase} = $occ if !exists $count{$phrase} || $occ > $count{$phrase};
}
# Perl 的字串排序是依碼位，與 Swift 依開頭字分組的方式一致
print "$_\t$count{$_}\n" for sort keys %count;
