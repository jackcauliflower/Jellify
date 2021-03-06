//
//  ArtistDetailView.swift
//  FinTune
//
//  Created by Jack Caulfield on 10/6/21.
//

import SwiftUI

struct ArtistDetailView: View {
    
    @Environment(\.managedObjectContext)
    var managedObjectContext
        
    var fetchRequest: FetchRequest<Album>
    
    var albums: FetchedResults<Album>{
        fetchRequest.wrappedValue
    }

    @State
    var albumResults : [AlbumResult] = []
    
    @State
    var search : String = ""
    
    @State
    var loading : Bool = true
	
	@Environment(\.presentationMode)
	var mode: Binding<PresentationMode>
	
	@EnvironmentObject
	var player : Player
	
	@EnvironmentObject
	var viewControls : ViewControls

	@State
    var artist : Artist
	    
    @ObservedObject
    var networkingManager : NetworkingManager = NetworkingManager.shared
	
	@State
	var artistToView : Artist?
	
	@State
	var navigateAway : Bool = false
	                
	init(_ artist: Artist) {

		self._artist = State(wrappedValue: artist)
		
        self.fetchRequest = FetchRequest(
            entity: Album.entity(),
			sortDescriptors: [
				NSSortDescriptor(key: #keyPath(Album.favorite), ascending: false),
				NSSortDescriptor(key: #keyPath(Album.productionYear), ascending: false)
			],
            predicate: NSPredicate(format: "albumArtistName == %@", artist.name!)
        )		
    }
    
    var body: some View {
                   
        VStack {
            
            List {
                
                HStack {
                    Spacer()
                    ArtistImage(artist: artist)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                
                HStack {
                    Spacer()
                    
                    Button(action: {
                        if artist.favorite {
                            networkingManager.unfavorite(jellyfinId: artist.jellyfinId!, originalValue: artist.favorite, complete: { result in
                                artist.favorite = result
                            })
                        } else {
                            networkingManager.favoriteItem(jellyfinId: artist.jellyfinId!, originalValue: artist.favorite, complete: { result in
                                artist.favorite = result
                            })
                        }
                    }, label: {
                        if artist.favorite {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.accentColor)
                                .font(.largeTitle)
                        } else {
                            Image(systemName: "heart")
                                .font(.largeTitle)
                        }
                    })
                        .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                .padding(.bottom, 15)

                ForEach(albums) { album in
                    AlbumRow(album: album, artist: artist)
                        .listRowSeparator(albums.last! == album ? .hidden : .visible)
                }
            }
            .listStyle(PlainListStyle())
            
//        .searchable(text: $search, prompt: "Search \(artist.name ?? "Unknown Artist") albums")
//        .onChange(of: search, perform: { newSearch in
//            albums.nsPredicate = newSearch.isEmpty ? nil : NSPredicate(format: "%K contains[c] %@", #keyPath(Album.name), newSearch)
//
//        })
        }
        .navigationTitle(artist.name ?? "Unknown Artist")
		.onAppear {
			self.viewControls.currentView = .ArtistDetail
			self.viewControls.showArtistView = false
		}
		.onChange(of: self.viewControls.showArtistView, perform: { newValue in
			if newValue && self.viewControls.currentView == .ArtistDetail {
				if let artist = player.currentArtist {
					
					self.artistToView = artist
					
					self.navigateAway = true
				}
			}
		})
		
		if self.artistToView != nil {
			NavigationLink(destination: NowPlayingArtistDetailView(artist: self.artistToView!), isActive: $navigateAway, label: {})
				.isDetailLink(false)
		}
    }
}
