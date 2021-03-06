;****************************************************************************
;Copyright © 2008-2011 Oregon State University
;All Rights Reserved.
;
;
;Permission to use, copy, modify, and distribute this software and its
;documentation for educational, research and non-profit purposes, without
;fee, and without a written agreement is hereby granted, provided that the
;above copyright notice, this paragraph and the following three paragraphs
;appear in all copies.
;
;
;Permission to incorporate this software into commercial products may be
;obtained by contacting Oregon State University Office of Technology Transfer.
;
;
;This software program and documentation are copyrighted by Oregon State
;University. The software program and documentation are supplied "as is",
;without any accompanying services from Oregon State University. OSU does not
;warrant that the operation of the program will be uninterrupted or
;error-free. The end-user understands that the program was developed for
;research purposes and is advised not to rely exclusively on the program for
;any reason.
;
;
;IN NO EVENT SHALL OREGON STATE UNIVERSITY BE LIABLE TO ANY PARTY FOR DIRECT,
;INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST
;PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN
;IF OREGON STATE UNIVERSITYHAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
;DAMAGE. OREGON STATE UNIVERSITY SPECIFICALLY DISCLAIMS ANY WARRANTIES,
;INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
;FITNESS FOR A PARTICULAR PURPOSE AND ANY STATUTORY WARRANTY OF
;NON-INFRINGEMENT. THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS,
;AND OREGON STATE UNIVERSITY HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE,
;SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
;
;****************************************************************************
;+
;
;
; HISTORY:
;   09.26.2011, add metadata create for all output files.
;   
;-
function process_tbcd_chunks, run_params
  ;copy over just to make it work with historical code.  lazy
  image_info = run_params.image_info
  index = run_params.index				;string with name of index
  subset=run_params.subset
  mask_image = run_params.mask_image
  output_base = run_params.output_base
  kernelsize = run_params.kernelsize
  
  background_val = run_params.background_val
  skipfactor = run_params.skipfactor
  desawtooth_val = run_params.desawtooth_val
  pval = run_params.pval
  max_segments = run_params.max_segments
  
  fix_doy_effect = run_params.fix_doy_effect
  divisor =run_params.divisor
  minneeded = run_params.minneeded
  recovery_threshold=run_params.recovery_threshold
  distweightfactor = run_params.distweightfactor
  vertexcountovershoot = run_params.vertexcountovershoot
  bestmodelproportion = run_params.bestmodelproportion
  
  ;make a directory
  file_mkdir, file_dirname(output_base)
  
  ;tests
  if vertexcountovershoot gt 3 then begin
    print, 'Vertexcountovershoot cannot exceed 3'
    return, -1
  end
  if bestmodelproportion gt 1 then begin
    print, 'bestmodelproportion cannot exceed 1.  Should be in the 0.5 to 1.0 range.'
    return, -1
  end
  
  ;first, check to see if the output image already exists.  If so
  ;   see if it has a save file to indicate that it was already in
  ;   process, and needs to just be picked up again
  diagfile =  output_base+'_diag.sav'
  
  if file_exists(diagfile) then begin
    print, 'This file has already had processing done on it'
    restore, diagfile
    
    image_info = diag_info.image_info
    index = diag_info.index
    mask_image = diag_info.mask_image
    output_image_group = diag_info.output_image_group
    
    n_chunks = diag_info.n_chunks
    chunks = diag_info.chunks
    current_chunk = diag_info.current_chunk
    pixels_per_chunk = diag_info.pixels_per_chunk
    kernelsize = diag_info.kernelsize
    
    background_val=diag_info.background_val
    skipfactor=diag_info.skipfactor
    desawtooth_val=diag_info.desawtooth_val
    pval=diag_info.pval
    max_segments=diag_info.max_segments
    ;  normalize=diag_info.normalize
    fix_doy_effect=diag_info.fix_doy_effect
    divisor=diag_info.divisor
    recovery_threshold = diag_info.recovery_threshold
    distweightfactor = diag_info.distweightfactor
    vertexcountovershoot = diag_info.vertexcountovershoot
    bestmodelproportion = diag_info.bestmodelproportion
  end else begin           ;if this image has not been set up before, then
    ;get set up to do it.
    ;SET UP THE OUTPUT FILE AND CHUNK INFORMATION
    ;First, set up the processing chunks
  
    if n_elements(max_pixels_per_chunk) eq 0 then $
      max_pixels_per_chunk = 500000l
      
    ;to get the pixel size of the image, assume that all are the same
    if file_exists(image_info[0].image_file) eq 0 then begin
      print, "process_cm_biomass_image.pro:  Image in
      print,"    image_list does not exist.  Failing."
      print,"    Image that was not found:
      print, image_info[0].image_file
    end
    
    mastersubset = subset
    subset = mastersubset
    zot_img, image_info[0].image_file, hdr, img, subset=subset, /hdronly
    pixsize = hdr.pixelsize
    
    ;now get the chunks
    subset = mastersubset
    ok = define_chunks3(subset, pixsize, max_pixels_per_chunk, kernelsize)
    if ok.ok eq 0 then return, {ok:0}

    ;stop
    chunks = ok.subsets
    pixels_per_chunk = ok.pixels_per_chunk
    n_chunks = n_elements(chunks)
    current_chunk = 0          ;an index
    
    ;define the output images
    ;vertices:   the years of the vertices
    ;vertvals:  the values of the input band at those years
    ;mags:   the magnitude of the segment change between two vertices
    ;distrec:  three layer image
    ;			1:  largest single disturbance
    ;			2:  largest single recovery
    ;			3:  scaled ratio between disturbance and recovery
    ;					-1000 is all recovery
    ;					0 is a balance
    ;					1000 is all disturbance

    ;fitted image
    ;			Same number of years as all of the inputs,
    ;			but with fitted values
    ;Stats image for entire fit
    ;			P of f
    ;			f_stat
    ;			ms_regr
    ;			ms_resid
    
    output_image_base = {filename:'', n_layers:0, extension:'', layersize:0l, filesize:0ll, DATA:""}
    
    output_image_group = replicate(output_image_base, 10)
    output_image_group[0].extension = 	'_vertyrs.bsq'
    output_image_group[0].n_layers  =  max_segments+1
    output_image_group[0].DATA  =  "Vertex Year"
    
    output_image_group[1].extension = 	'_vertvals.bsq'
    output_image_group[1].n_layers  =  max_segments+1
    output_image_group[1].DATA  =  "Vertex Spectral Value"
    
    output_image_group[2].extension = 	'_mags.bsq'
    output_image_group[2].n_layers  =  max_segments
    output_image_group[2].DATA  =  "Segment Magnitude"
    
    
    output_image_group[3].extension = 	'_durs.bsq'
    output_image_group[3].n_layers  =  max_segments
    output_image_group[3].DATA  =  "Segment Duration"
    
    output_image_group[4].extension = 	'_distrec.bsq'
    output_image_group[4].n_layers  =  3
    output_image_group[4].DATA  =  "Trajectory Disturbance/Recovery"
    
    ;6/27/08 for fitted image, the output will be the
    ;   max of 1 image per year.  If multiple images
    ;   in a given year are provided with the idea of doing
    ;   cloud-mosaicking, then we need to compensate for
    ;   those doubled-images in stack.
    
    years = image_info.year
    un_years = fast_unique(years)
    years = un_years[sort(un_years)]
    
    output_image_group[5].extension = 	'_fitted.bsq'
    output_image_group[5].n_layers  =  n_elements(years)
    output_image_group[5].DATA  =  "Fitted Spectral Stack"

    output_image_group[6].extension = 	'_stats.bsq'
    output_image_group[6].n_layers  =  10
    output_image_group[6].DATA  =  "Segment Statistics"

    output_image_group[7].extension = 	'_segmse.bsq'
    output_image_group[7].n_layers  =  max_segments
    output_image_group[7].DATA  =  "Segment MSE"
    
    output_image_group[8].extension = 	'_source.bsq'
    output_image_group[8].n_layers  =  n_elements(years)
    output_image_group[8].DATA  =  "Source Spectral Stack"

    output_image_group[9].extension = 	'_segmean.bsq'
    output_image_group[9].n_layers  =  max_segments
    output_image_group[9].DATA  =  "Segment Mean Spectral"
    
    ;this_tag = "_" + timestamp() + "_" + landtrendr_version()
    for i = 0, n_elements(output_image_group)-1 do begin

      this_file = output_base + output_image_group[i].extension
      output_image_group[i].filename = this_file
      
      openw, un, 	output_image_group[i].filename, /get_lun
      n_output_layers = output_image_group[i].n_layers
      
      bytes_per_pixel = 2
      layersize = long(hdr.filesize[0]) * hdr.filesize[1] * bytes_per_pixel
        
      filesize = ulong64(layersize) * n_output_layers
      point_lun, un, filesize - 2         ;-2 because we're going to write
      ;a blank pixel
      writeu, un, 0
      free_lun, un         ;now the file exists on the drive.
      hdr1 = hdr
      hdr1.n_layers = n_output_layers
      hdr1.pixeltype = 6
      hdr1.upperleftcenter = subset[*,0]
      hdr1.lowerrightcenter = subset[*,1]
      write_im_hdr, 	output_image_group[i].filename, hdr1
      output_image_group[i].layersize = layersize
      output_image_group[i].filesize = filesize

      ; now create the metadata file
      this_meta = stringswap(this_file, ".bsq", "_meta.txt")

      files = file_basename(image_info.image_file)+[replicate(','+string(10b), n_elements(image_info)-1), '']
      files = string(files, format='('+string(n_elements(files))+'A)')      
      meta = create_struct("DATA", output_image_group[i].DATA, "FILENAME", file_basename(this_file), "PARENT_FILE", files, run_params)
      
;      concatenate_metadata, image_info.image_file, this_meta, params=meta
    end		;going through images
    
    ;2/7/08  First determine the scaling factor, so
    ;  the image is always in the 0-1000 range.
    
    ;pick the middle image and look at the max
    n_files = n_elements(image_info)
    pickit = n_files/2
    landtrendr_image_read, image_info[pickit], hdr, img1, subset, index, modifier, background_val
    
    ;if user asks for divisor to be calc'd, do it here
    if divisor eq -1 then begin
      divscale = [1., 10, 100, 1000, 10000, 100000]		; raise 10 to the power of the appropriate index to get divisor
      m1 = median(img1)
      div = float(m1)/ 1000		;divide by the number you want to be max
      divisor = 10 ^ (min(where(divscale gt div)))
    end
    
    img1 = 0 ;for memory

    ;now write out the diagnostic file so we can keep
    ;   track of what we've complete, in case things crash.
    diag_info = $
      {image_info:image_info, $
      index:index, $
      mask_image:mask_image, $
      output_image_group:output_image_group, $
      pixels_per_chunk:pixels_per_chunk, $
      
      n_chunks:n_chunks, $
      chunks:chunks, $
      current_chunk:current_chunk, $
      version_number:landtrendr_version(), $
      kernelsize:kernelsize, $
      
      background_val:background_val, $
      skipfactor:skipfactor, $
      desawtooth_val:desawtooth_val, $
      pval:pval, $
      max_segments:max_segments, $
      ;normalize:n_elements(normalize), $
      fix_doy_effect:fix_doy_effect, $
      divisor:divisor, $
      recovery_threshold:recovery_threshold, $
      distweightfactor:distweightfactor, $
      vertexcountovershoot:vertexcountovershoot, $
      bestmodelproportion:bestmodelproportion $
      }

    save, diag_info, file = diagfile
  end
  
  ;at this point, we've either created or restored the diag_info
  ;  this tells us what the chunks are, and what we've written
  ;  to the output image. "Current_chunk" is the important
  ;  index that lets us know where we are in the processing.
  
  ;set up the progress bar:
  mainprogressBar = Obj_New("PROGRESSBAR", /fast_loop, title = 'Processing chunks')
  mainprogressBar -> Start
  
  ;get set up with the correct information, based on the chunk
  thebeginning:
  
  ;diagnosis stuff; comment out for final run
  if current_chunk ge n_chunks then begin
    print, 'This image has been entirely processed.'
    print, 'If you want to reprocess it, please delete this file:'
    print, diagfile
    mainprogressBar -> Destroy
    return, {ok:0}
  end
  
  ;first, where in the input files do we look?
  subset = chunks[current_chunk].coords
  
  ;second, where do we write out?
  ;calculated in define_chunks2, but in pixel units..
  ;  for file units, need to multiply by 2 because 2 bytes per pixel
  ;  in integer world.
  within_layer_offset = chunks[current_chunk].within_layer_offset * 2
  
  ok = run_tbcd_single_chunk(image_info, $
    subset, index, mask_image, output_image_group, $
    within_layer_offset, layersize, kernelsize, $
    background_val, $
    skipfactor, desawtooth_val, $
    pval, max_segments, normalize, $
    fix_doy_effect, divisor, recovery_threshold, $
    minneeded, distweightfactor, vertexcountovershoot, $
    bestmodelproportion )
    
  ;check on main progress bar
  if mainprogressBar -> CheckCancel() then begin
    mainprogressBar -> destroy
    print, 'chunk', string(current_chunk)
  end
  
  ;increment chunk, keep track of it in case program
  ;   crashes in next piece
  current_chunk = current_chunk + 1
  diag_info.current_chunk = current_chunk
  save, diag_info, file = diagfile
  
  ;update the progress meeter
  percent_done = float(current_chunk)/n_chunks
  mainprogressBar -> Update, percent_done*100, text = strcompress('Done with chunk '+string(current_chunk)+' of '+string(n_chunks))
  
  if current_chunk lt n_chunks then goto, thebeginning
  
  ;interpolation.
  print, "Done."
  mainprogressBar -> destroy
  
  return, {ok:1}
end
