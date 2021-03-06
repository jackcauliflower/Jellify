//
//  ArtistThumbnail.swift
//  FinTune (iOS)
//
//  Created by Jack Caulfield on 10/24/21.
//

import SwiftUI

struct ArtistThumbnail: View {
    
    @ObservedObject
    var artist : FetchedResults<Artist>.Element
    
    let networkingManager : NetworkingManager = NetworkingManager.shared
    
    var body: some View {
        ItemThumbnail(itemId: artist.jellyfinId!, frame: 60, cornerRadius: 100)
//            .onAppear(perform: {
//                networkingManager.imageQueue.async {
//                    if (artist.thumbnail == nil) {
//                        networkingManager.loadArtistImage(artist: artist)
//                    }
//                }
//            })
    }
}
