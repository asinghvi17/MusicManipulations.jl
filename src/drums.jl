module Drums
using MusicManipulations

# all pitches of digitally connected instruments that support extra velocities
const DIGITAL = [0x26,0x28,0x33,0x35,0x3b]

"""
    getnotes_td50(track::MIDITrack, tpq = 960)

Get notes from midi track. Take care of Roland TD-50's ability to have velocities up to 159 for snare and ride.
"""
function getnotes_td50(track::MIDI.MIDITrack, tpq = 960)
    notes = MoreVelNote[]
    tracktime = UInt(0)
    extravel = 0
    for (i, event) in enumerate(track.events)
        tracktime += event.dT
        # Read through events until a noteon with velocity higher tha 0 is found
        if isa(event, MIDIEvent) && event.status & 0xF0 == NOTEON && event.data[2] > 0
            duration = UInt(0)
            #Test if the next event is an extra velocity event and modify velocity if needed.
            if event.data[1] in DIGITAL && event.data[2]==0x7f && track.events[i+1].status==0xb0 && track.events[i+1].data[1]==0x58
                extravel = floor(UInt8,track.events[i+1].data[2]/2)
                if extravel > 32
                    extravel = 32
                end
            end
            #Test if the previous event is an extra velocity event and modify velocity if needed.
            if i>2 #first event is alwas METAEvent
                if event.data[1] in DIGITAL && event.data[2]==0x7f && track.events[i-1].status==0xb0 && track.events[i-1].data[1]==0x58
                    extravel = floor(UInt8,track.events[i-1].data[2]/2)
                    if extravel > 32
                        extravel = 32
                    end
                end
            end
            for event2 in track.events[i+1:length(track.events)]
                duration += event2.dT
                # If we have a MIDI event & it's a noteoff (or a note on with 0 velocity), and it's for the same note as the first event we found, make a note
                # Many MIDI files will encode note offs as note ons with velocity zero
                if isa(event2, MIDI.MIDIEvent) && (event2.status & 0xF0 == MIDI.NOTEOFF || (event2.status & 0xF0 == MIDI.NOTEON && event2.data[2] == 0)) && event.data[1] == event2.data[1]
                    push!(notes, MoreVelNote(event.data[1], event.data[2]+extravel, tracktime, duration, event.status & 0x0F))
                    break
                end
            end
            extravel = 0
        end
    end
    sort!(notes, lt=((x, y)->x.position<y.position))
    return Notes(notes, tpq)
end


"""
    rm_hihatfake(notes::MIDI.Notes, BACK = 100, FORW = 100, CUTOFF = 0x16)

Remove fake tip notes generated by Hihat at certain actions by spotting them and
just removing every Hihat Head event with velocity less than `CUTOFF`and position
maximum `BACK` ticks before or `FORW` ticks after foot close.
"""
function rm_hihatfake!(notes::MIDI.Notes, BACK = 100, FORW = 100, CUTOFF = 0x16)

    #first map special closed notes
    for note in notes
        if note.pitch == 0x16
            note.pitch = 0x1a
        elseif note.pitch == 0x2a
            note.pitch = 0x2e
        end
    end
    #then look for fake notes
   i = 1
   deleted = 0
   len = length(notes)
   while i <= len
      #find foot close
      if notes[i].pitch == 0x2c || notes[i].pitch == 0x1a
         #go back and remove all fake tip strokes
         j = i-1
         #search all notes in specified BACK region
         while j>0 && notes[i].position-notes[j].position < BACK
            #if they are quiet enough
            if notes[j].pitch == 0x2e && notes[j].velocity <= CUTOFF
               #remove them
               deleteat!(notes.notes,j)
               deleted += 1
               i-=1
               len-=1
            else
               j-=1
            end
         end
         #go forward and remove all fake tip strokes
         j=i+1
         #search all notes in specified FORW region
         while j<=len && notes[j].position-notes[i].position < FORW
            #if they are quiet enough
            if notes[j].pitch == 0x2e && notes[j].velocity <= CUTOFF
               #remove them
               deleteat!(notes.notes,j)
               deleted += 1
               len-=1
            else
               j+=1
            end
         end
      end
      i+=1
   end
   println("deleted $(deleted) fake notes")
end


# Map the pitches of midinotes to Instruments of Roland TD-50
const MAP_TD50 = Dict{UInt8,String}(
    0x16=>"Hihat Rim (closed)",
    0x1a=>"Hihat Rim",
    0x24=>"Kick",
    0x25=>"Snare RimClick",
    0x26=>"Snare",
    0x27=>"Tom 4 Rimshot",
    0x28=>"Snare Rimshot",
    0x29=>"Tom 4",
    0x2a=>"Hihat Head (closed)",
    0x2b=>"Tom 3",
    0x2c=>"Hihat Foot Close",
    0x2d=>"Tom 2",
    0x2e=>"Hihat Head",
    0x2f=>"Tom 2 Rimshot",
    0x30=>"Tom 1",
    0x31=>"Cymbal 1",
    0x32=>"Tom 1 Rimshot",
    0x33=>"Ride Head",
    0x34=>"Cymbal 2",
    0x35=>"Ride Bell",
    0x37=>"Cymbal 1",
    0x39=>"Cymbal 2",
    0x3a=>"Tom 3 Rimshot",
    0x3b=>"Ride Rim")

# All posible pitches in an Array
const ALLPITCHES_TD50 = collect(keys(MAP_TD50))

# Map the pitches to numbers for plotting in a graph
const REORDER_TD50 = Dict{UInt8,UInt8}(
    0x16=>8,
    0x1a=>5,
    0x24=>0,
    0x25=>3,
    0x26=>1,
    0x27=>19,
    0x28=>2,
    0x29=>18,
    0x2a=>7,
    0x2b=>16,
    0x2c=>6,
    0x2d=>14,
    0x2e=>4,
    0x2f=>15,
    0x30=>12,
    0x31=>20,
    0x32=>13,
    0x33=>9,
    0x34=>21,
    0x35=>11,
    0x37=>20,
    0x39=>21,
    0x3a=>17,
    0x3b=>10)

###############################################################################
#velocity quantization
###############################################################################

"""
    td50_velquant_interval(notes::MIDI.Notes, numintervals::Int)

Divide the velocity range in `numintervals` intervals and quantize the
velocities of each `Note` to the mean value of all notes of the corresponding
instrument in this interval.
"""
function td50_velquant_interval(notes::MIDI.Notes{N}, numintervals::Int) where {N}
    #get notes separated by pitches
    sep = separatepitches(notes)
    newnotes = MIDI.Notes{N}(Vector{N}(), notes.tpq)

    for pitch in keys(sep)
        #short acces to needed notes
        pitchnotes = sep[pitch].notes

        #take care of different maximum velocities
        maxvel = 0
        pitch in DIGITAL ? maxvel = 160 : maxvel = 128

        #do a histogram and weight it with the velocities
        hist = zeros(maxvel)
        for note in pitchnotes
            hist[note.velocity] += 1
        end
        whist = copy(hist)
        for i = 1:length(hist)
            whist[i] *= i
        end

        #create the partitioning and compute corresponding means
        intlength = ceil(Int, maxvel/numintervals)
        meanvals = zeros(Int, numintervals)
        for i = 0:numintervals-1
            start = i*intlength+1
            ende = i*intlength+intlength
            if ende > maxvel
                ende = maxvel
            end
            piece = whist[start:ende]
            hits = sum(hist[start:ende])
            if hits != 0
                piece ./= hits
            end
            meanvals[i+1] = round(Int,mean(piece)*intlength)
        end

        #quantize notes
        for note in pitchnotes
            quant = ceil(Int, note.velocity/intlength)
            note.velocity = meanvals[quant]
        end

        # append to field of quantized notes
        append!(newnotes.notes, pitchnotes)
    end

    #restore temporal order
    sort!(newnotes.notes, lt=((x, y)->x.position<y.position))
    return newnotes
end

end
