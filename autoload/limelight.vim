" Copyright (c) 2015 Junegunn Choi
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

let s:default_coeff = str2float('0.5')
let s:invalid_coefficient = 'Invalid coefficient. Expected: 0.0 ~ 1.0'

function! s:unsupported()
  let var = 'g:limelight_conceal_'.(has('gui_running') ? 'gui' : 'cterm').'fg'

  if exists(var)
    return 'Cannot calculate background color.'
  else
    return 'Unsupported color scheme. '.var.' required.'
  endif
endfunction

function! s:getpos()
  let bop = get(g:, 'limelight_bop', '^\s*$\n\zs')
  let eop = get(g:, 'limelight_eop', '^\s*$')
  let span = max([0, get(g:, 'limelight_paragraph_span', 0) - s:empty(getline('.'))])
  let pos = exists('*getcurpos')? getcurpos() : getpos('.')
  for i in range(0, span)
    let start = searchpos(bop, i == 0 ? 'cbW' : 'bW')[0]
  endfor
  call setpos('.', pos)
  for _ in range(0, span)
    let end = searchpos(eop, 'W')[0]
  endfor
  call setpos('.', pos)
  return [start, end]
endfunction

function! s:empty(line)
  return (a:line =~# '^\s*$')
endfunction

function! s:limelight()
  if !empty(get(w:, 'limelight_range', []))
    return
  endif
  if !exists('w:limelight_prev')
    let w:limelight_prev = [0, 0, 0, 0]
  endif

  let curr = [line('.'), line('$')]
  if curr ==# w:limelight_prev[0 : 1]
    return
  endif

  let paragraph = s:getpos()
  if paragraph ==# w:limelight_prev[2 : 3]
    return
  endif

  call s:clear_hl()
  call call('s:hl', paragraph)
  let w:limelight_prev = extend(curr, paragraph)
endfunction

function! s:hl(startline, endline)
  let w:limelight_match_ids = get(w:, 'limelight_match_ids', [])
  let priority = get(g:, 'limelight_priority', 10)
  call add(w:limelight_match_ids, matchadd('LimelightDim', '\%<'.a:startline.'l', priority))
  if a:endline > 0
    call add(w:limelight_match_ids, matchadd('LimelightDim', '\%>'.a:endline.'l', priority))
  endif
endfunction

function! s:clear_hl()
  while exists('w:limelight_match_ids') && !empty(w:limelight_match_ids)
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

  if has('gui_running') || has('termguicolors') && &termguicolors || has('nvim') && $NVIM_TUI_ENABLE_TRUE_COLOR
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
    execute printf('hi LimelightDim guifg=%s guisp=bg', dim)
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

function! s:on(range, ...)
  try
    let s:limelight_coeff = a:0 > 0 ? s:parse_coeff(a:1) : -1
    call s:dim(s:limelight_coeff)
  catch
    return s:error(v:exception)
  endtry

  let w:limelight_range = a:range
  if !empty(a:range)
    call s:clear_hl()
    call call('s:hl', a:range)
  endif

  augroup limelight
    let was_on = exists('#limelight#CursorMoved')
    autocmd!
    if empty(a:range) || was_on
      autocmd CursorMoved,CursorMovedI * call s:limelight()
    endif
    autocmd ColorScheme * try
                       \|   call s:dim(s:limelight_coeff)
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
  call s:clear_hl()
  augroup limelight
    autocmd!
  augroup END
  augroup! limelight
  unlet! w:limelight_prev w:limelight_match_ids w:limelight_range
endfunction

function! s:is_on()
  return exists('#limelight')
endfunction

function! s:cleanup()
  if !s:is_on()
    call s:clear_hl()
  end
endfunction

function! limelight#execute(bang, visual, line1, line2, ...)
  let range = a:visual ? [a:line1, a:line2] : []
  if a:bang
    if a:0 > 0 && a:1 =~ '^!' && !s:is_on()
      if len(a:1) > 1
        call s:on(range, a:1[1:-1])
      else
        call s:on(range)
      endif
    else
      call s:off()
    endif
  elseif a:0 > 0
    call s:on(range, a:1)
  else
    call s:on(range)
  endif
endfunction

function! limelight#operator(...)
  call limelight#execute(0, 1, line("'["), line("']"))
endfunction

let &cpo = s:cpo_save
unlet s:cpo_save

