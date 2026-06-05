import win32com.client
try:
    sdb = win32com.client.Dispatch("SongsDB.SDBApplication")
    song = sdb.NewSongData
    song.Path = r"E:\Data\Rajesh\MyMusic\Music_AI_Vault\test.wav"
    song.Title = "Test Song API"
    song.UpdateDB()
    song.UpdateAll()
    print("Song ID:", song.SongID)
except Exception as e:
    print("Error:", e)
