" Copyright (c) 2014 Junegunn Choi
"
" MIT License
"
" Permission is hereby granted, free of charge, to any person obtaining
" a copy of this software and associated documentation files (the
" "Software"), to deal in the Software without restriction, including
" without limitation the rights to use, copy, modify, merge, publish,
" distribute, sublicense, and/or sell copies of the Software, and to
" permit persons to whom the Software is furnished to do so, subject to
" the following conditions:
"
" The above copyright notice and this permission notice shall be
" included in all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
" EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
" MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
" NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
" LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
" OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
" WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

if exists('g:loaded_limelight')
  finish
endif
let g:loaded_limelight = 1

let s:cpo_save = &cpo
set cpo&vim

let s:default_coeff = 0.5
let s:invalid_coefficient = 'Invalid coefficient. Expected: 0.0 ~ 1.0'

function! s:unsupported()
  let var = 'g:limelight_conceal_'.(has('gui_running') ? 'gui' : 'cterm').'fg'

  if exists(var)
    return 'Cannot calculate background color.'
  else
    return 'Unsupported color scheme. '.var.' fg required.'
  endif
endfunction

function! s:limelight()
  if !exists('w:limelight_prev')
    let w:limelight_prev = [0, 0, 0, 0]
  endif
  if !exists('w:limelight_match_ids')
    let w:limelight_match_ids = []
  endif

  let curr = [line('.'), line('$')]
  if curr ==# w:limelight_prev[0 : 1]
    return
  endif

  let paragraph = [searchpos('^$', 'bnW')[0], searchpos('^$', 'nW')[0]]
  if paragraph ==# w:limelight_prev[2 : 3]
    return
  endif

  call s:clear_hl()
  call add(w:limelight_match_ids, matchadd('LimelightDim', '\%<'.paragraph[0].'l'))
  if paragraph[1] > 0
    call add(w:limelight_match_ids, matchadd('LimelightDim', '\%>'.paragraph[1].'l'))
  endif
  let w:limelight_prev = extend(curr, paragraph)
endfunction

function! s:clear_hl()
  while !empty(w:limelight_match_ids)
    silent! call matchdelete(remove(w:limelight_match_ids, -1))
  endwhile
endfunction

function! s:hex2rgb(str)
  let str = substitute(a:str, '^#', '', '')
  return [eval('0x'.str[0:1]), eval('0x'.str[2:3]), eval('0x'.str[4:5])]
endfunction

let s:gray_converter = {
\ 0:   231,
\ 7:   254,
\ 15:  256,
\ 16:  231,
\ 231: 256
\ }

function! s:gray_contiguous(col)
  let val = get(s:gray_converter, a:col, a:col)
  if val < 231 || val > 256
    throw s:unsupported()
  endif
  return val
endfunction

function! s:gray_ansi(col)
  return a:col == 231 ? 0 : (a:col == 256 ? 231 : a:col)
endfunction

function! s:coeff(coeff)
  let coeff = a:coeff < 0 ?
        \ get(g:, 'limelight_default_coefficient', s:default_coeff) : a:coeff
  if coeff < 0 || coeff > 1
    throw 'Invalid g:limelight_default_coefficient. Expected: 0.0 ~ 1.0'
  endif
  return coeff
endfunction

function! s:dim(coeff)
  let synid = synIDtrans(hlID('Normal'))
  let fg = synIDattr(synid, 'fg#')
  let bg = synIDattr(synid, 'bg#')

  if has('gui_running')
    if a:coeff < 0 && exists('g:limelight_conceal_guifg')
      let dim = g:limelight_conceal_guifg
    elseif empty(fg) || empty(bg)
      throw s:unsupported()
    else
      let coeff = s:coeff(a:coeff)
      let fg_rgb = s:hex2rgb(fg)
      let bg_rgb = s:hex2rgb(bg)
      let dim_rgb = [
            \ bg_rgb[0] * coeff + fg_rgb[0] * (1 - coeff),
            \ bg_rgb[1] * coeff + fg_rgb[1] * (1 - coeff),
            \ bg_rgb[2] * coeff + fg_rgb[2] * (1 - coeff)]
      let dim = '#'.join(map(dim_rgb, 'printf("%x", float2nr(v:val))'), '')
    endif
    execute printf('hi LimelightDim guifg=%s', dim)
  elseif &t_Co == 256
    if a:coeff < 0 && exists('g:limelight_conceal_ctermfg')
      let dim = g:limelight_conceal_ctermfg
    elseif fg <= -1 || bg <= -1
      throw s:unsupported()
    else
      let coeff = s:coeff(a:coeff)
      let fg = s:gray_contiguous(fg)
      let bg = s:gray_contiguous(bg)
      let dim = s:gray_ansi(float2nr(bg * coeff + fg * (1 - coeff)))
    endif
    if type(dim) == 1
      execute printf('hi LimelightDim ctermfg=%s', dim)
    else
      execute printf('hi LimelightDim ctermfg=%d', dim)
    endif
  else
    throw 'Unsupported terminal. Sorry.'
  endif
endfunction

function! s:error(msg)
  echohl ErrorMsg
  echo a:msg
  echohl None
endfunction

function! s:parse_coeff(coeff)
  let t = type(a:coeff)
  if t == 1
    if a:coeff =~ '^ *[0-9.]\+ *$'
      let c = str2float(a:coeff)
    else
      throw s:invalid_coefficient
    endif
  elseif index([0, 5], t) >= 0
    let c = t
  else
    throw s:invalid_coefficient
  endif
  return c
endfunction

function! s:on(...)
  try
    let s:limelight_coeff = a:0 > 0 ? s:parse_coeff(a:1) : -1
    call s:dim(s:limelight_coeff)
  catch
    return s:error(v:exception)
  endtry

  augroup limelight
    autocmd!
    autocmd CursorMoved,CursorMovedI * call s:limelight()
    autocmd ColorScheme * try
                       \|   call s:dim(s:limelight_coeff)
                       \|   call s:limelight()
                       \| catch
                       \|   call s:off()
                       \|   throw v:exception
                       \| endtry
  augroup END

  " FIXME: We cannot safely remove this group once Limelight started
  augroup limelight_cleanup
    autocmd!
    autocmd WinEnter * call s:cleanup()
  augroup END

  doautocmd CursorMoved
endfunction

function! s:off()
  if exists('w:limelight_match_ids')
    call s:clear_hl()
  endif
  augroup limelight
    autocmd!
  augroup END
  augroup! limelight
  unlet! w:limelight_prev w:limelight_match_ids
endfunction

function! s:is_on()
  return exists('#limelight')
endfunction

function! s:do(bang, ...)
  if a:bang
    if a:0 > 0 && a:1 =~ '^!' && !s:is_on()
      if len(a:1) > 1
        call s:on(a:1[1:-1])
      else
        call s:on()
      endif
    else
      call s:off()
    endif
  elseif a:0 > 0
    call s:on(a:1)
  else
    call s:on()
  endif
endfunction

function! s:cleanup()
  if !s:is_on() && exists('w:limelight_match_ids')
    call s:clear_hl()
  end
endfunction

command! -nargs=? -bar -bang Limelight call s:do('<bang>' == '!', <f-args>)

let &cpo = s:cpo_save
unlet s:cpo_save

