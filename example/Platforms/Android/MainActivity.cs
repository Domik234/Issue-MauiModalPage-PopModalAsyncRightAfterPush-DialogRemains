using Android.App;
using Android.Content.PM;
using Android.OS;

namespace ModalRaceRepro;

[Activity(Theme = "@style/Maui.SplashTheme", MainLauncher = true, LaunchMode = LaunchMode.SingleTop, ConfigurationChanges = ConfigChanges.ScreenSize | ConfigChanges.Orientation | ConfigChanges.UiMode | ConfigChanges.ScreenLayout | ConfigChanges.SmallestScreenSize | ConfigChanges.Density)]
public class MainActivity : MauiAppCompatActivity
{
    protected override void OnCreate(Android.OS.Bundle? savedInstanceState)
    {
        if (Intent?.HasExtra("delay_ms") == true)
            ModalRaceRepro.App.AutoRunDelayMs = Intent.GetIntExtra("delay_ms", 0);

        base.OnCreate(savedInstanceState);
    }

}
