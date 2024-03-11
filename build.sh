#!/usr/bin/env bash

set -e

# -- utils

pushd() {
    command pushd "$@" > /dev/null
}

popd() {
    command popd "$@" > /dev/null
}

bold() {
    printf '\033[1m%s\033[22m' "$@"
}

dim() {
    printf '\033[2m%s\033[22m' "$@"
}

red() {
    printf '\033[31m%s\033[39m' "$@"
}

green() {
    printf '\033[32m%s\033[39m' "$@"
}

cyan() {
    printf '\033[36m%s\033[39m' "$@"
}

has() {
  command -v $1 2>&1 >/dev/null
}

msg() {
    printf " \033[36;1m%s\033[m%s\n" "$PROMPT" "$*"
}

warn() {
    >&2 printf "\033[33;1m%s \033[mwarning: %s\n" "$PROMPT" "$*"
}

die() {
    >&2 printf "\033[31;1m%s \033[merror: %s\n" "$PROMPT" "$*"
    exit 1
}

# -- dependencies

check_dependencies() {
  for dep in "$@"; do
    has "$dep" || {
      echo "$(red "Error: $(bold "$dep") is required.")"
      exit 1
    }
  done
}

# -- variables

maple_version="v6.4"
nerd_fonts_version="v3.1.1"
font_family="SukiMono"

# -- main

# run in root
download_font_patcher() {
  [[ -d "_fontpatcher" ]] && return 0
  curl -fsSL -o FontPatcher.zip \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/$nerd_fonts_version/FontPatcher.zip"
  unzip FontPatcher.zip -d _fontpatcher
  rm FontPatcher.zip
}

# run in root
build_archive() {
  [[ -z "$1" ]] && return 1
  [[ -d "$1" ]] || return 1
  indir="$(basename $1)"
  font_name="$2"
  [[ -z "$font_name" ]] && font_name="$indir"
  [[ -d "dist/${font_name}" ]] && return 0
  msg "$(dim "build archives for src/out/${indir} to dist/${font_name}")"
  create_archives "src/out/${indir}" "dist/${font_name}"
}

# run in root
create_archives() {
  indir="$1"
  outfile="$2"
  [[ -d "$indir" ]] || return 1
  has zip && zip -r -9 "${outfile}.zip" "$indir"/*
  has tar && tar --gzip -cvf "${outfile}.tar.gz" "$indir"/*
  has tar && tar --xz -cvf "${outfile}.tar.xz" "$indir"/*
}

# run in src/Maple-font/source
create_venv() {
  msg "$(dim "create venv in .venv")"
  python -m venv ./.venv
  ./.venv/bin/pip install fontTools
  ./.venv/bin/pip install -r requirements.txt
}

# run in src
import_glyphs() {
  outdir="_fontpatcher/src/glyphs"
  import_version="1.002"
  msg "$(dim "importing SourceHanMono $import_version")"
  import_file="${outdir}/SourceHanMono.ttc"
  [[ -f "$import_file" ]] || curl -fsSL "https://github.com/adobe-fonts/source-han-mono/releases/download/${import_version}/SourceHanMono.ttc" -o "$import_file"
}

# in src
build_font() {
  [[ -z "$1" ]] && { warn "not enought arguments specified"; return 1; }
  [[ -f "$1" ]] || { warn "file $1 does not exist"; return 1; }
  font_file="$1"
  [[ -d "_fontpatcher" ]] || { "fontpatcher is not in current dir"; return 1; }
  fontforge -script _fontpatcher/font-patcher --quiet --complete --outputdir out --name "$2" "$font_file"
}

# in root
create_release() {
  [[ -d "src/out" ]] || { warn "src/out does not exist"; return 1; }

  mkdir -p dist

  msg "$(dim "organizing src/out")"

  msg "$(dim "- src/out/ttf")"
  mkdir -p src/out/ttf
  for item in $(find src/out -type f -name 'SukiMono-*.ttf'); do
    mv -f $item src/out/ttf
  done

  msg "$(dim "- src/out/NF")"
  mkdir -p src/out/NF
  for item in $(find src/out -type f -name 'SukiMonoNF-*.ttf'); do
    mv -f $item src/out/NF
  done

  for item in $(find "src/out" -type 'd'); do
    msg "$(dim "archiving $item")"
    build_archive "$item" "SukiMono$(basename ${item})"
  done

  msg "$(dim "Suki Mono Archives build to 'dist'")"
}

main() {
  flag="$1"
  shift 1
  case $flag in
    release) create_release $@; exit 0 ;;
    *) ;;
  esac
  msg "$(bold "suki-mono $(git tag -l 'v*' | tail -n 1)")"

  PROMPT="Maple        " msg "$maple_version"
  PROMPT="Nerd Fonts   " msg "$nerd_fonts_version"
  PROMPT="FontForge    " msg "$(fontforge -version 2> /dev/null | sed -n 's|fontforge ||p')"

  msg "$(dim "building $font_family")"

  msg "$(dim "importing NF patcher")"
  download_font_patcher

  mkdir -p src
  pushd src
  [[ -d "Maple-font" ]] || git clone --depth 1 https://github.com/subframe7536/Maple-font
  cp -f ../maple_build.py ./Maple-font/source/build.py
  cp -r ../_fontpatcher ./Maple-font/source/FontPatcher
  pushd ./Maple-font/source
  msg "$(dim "building Maple Mono")"
  [[ -d ".venv" ]] || create_venv
  [[ -d "../output" ]] || ./.venv/bin/python build.py
  popd # in src
  msg "$(dim "Maple Mono build to 'src/Maple-font/output'")"

  msg "$(dim "building $font_family")"

  mkdir -p out
  [[ -d "_fontpatcher" ]] || {
    cp -r ../_fontpatcher ./_fontpatcher;
    cp -f ../custom-font-patcher ./_fontpatcher/font-patcher;
    find ./_fontpatcher/src/glyphs -type f -name '*' -print0 | xargs -0 rm;
    find ./_fontpatcher/src/glyphs -mindepth 1 -type d -name '*' -print0 | xargs -0 rm -d;
  }
  msg "$(dim "importing glyphs")"
  import_glyphs
  vari=("ttf" "NF")
  msg "$(dim "building fonts")"
  for v in ${vari[@]}; do
    for item in $(find "Maple-font/output/$v/" -name '*.ttf'); do
      msg "$(dim "merge font $item")"
      suffix=""
      [[ "$v" == "NF" ]] && suffix="NF"
      name="$(basename $item)"
      style="$(echo ${name%.*} | sed -e 's/MapleMono\(-NF\)*-//')"
      name="SukiMono$suffix-$style"
      build_font "$item" "$name" || warn "error while merging $item"
    done
  done
  msg "$(dim "Suki Mono build to 'src/out'")"

  popd # in root
  msg "$(green "font generation succesfull")"
  msg "run \`./build.sh release\` to create release builds"
}

check_dependencies \
    printf echo rm mkdir find xargs \
    git curl \
    unzip tar cp

main "$@" || exit 1
