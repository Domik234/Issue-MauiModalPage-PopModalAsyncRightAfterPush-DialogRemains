namespace ModalRaceRepro;

public partial class MainPage : ContentPage
{
    public MainPage() => InitializeComponent();

    // Automatic run for the scripted check: adb shell am start ... --ei delay_ms <ms>
    protected override async void OnAppearing()
    {
        base.OnAppearing();

        if (App.AutoRunDelayMs is { } delay)
        {
            App.AutoRunDelayMs = null;
            await Task.Delay(3000);   // wait until the window page is loaded
            await Run(delay);
        }
    }

    async void OnImmediate(object sender, EventArgs e) => await Run(0);

    async void OnDelayed(object sender, EventArgs e) => await Run(1000);

    async Task Run(int delayBeforePopMs)
    {
        var modal = new ContentPage
        {
            BackgroundColor = Colors.Yellow,
            Content = new Label { Text = "MODAL - this page must be gone after PopModalAsync", HorizontalOptions = LayoutOptions.Center, VerticalOptions = LayoutOptions.Center },
        };

        await Navigation.PushModalAsync(modal, false);

        if (delayBeforePopMs > 0)
            await Task.Delay(delayBeforePopMs);

        var loadedAtPop = modal.IsLoaded;

        await Navigation.PopModalAsync(false);
        await Task.Delay(1500);

        var dialogs = ShowingDialogs();
        var result = $"delay before pop = {delayBeforePopMs} ms, modal.IsLoaded at pop = {loadedAtPop}, ModalStack = {Navigation.ModalStack.Count}, modal dialogs still showing = {dialogs}";
        Status.Text = result;
        Console.WriteLine("[REPRO] " + result);
    }

    static int ShowingDialogs()
    {
#if ANDROID
        return (Platform.CurrentActivity as AndroidX.Fragment.App.FragmentActivity)?.SupportFragmentManager.Fragments
            .OfType<AndroidX.Fragment.App.DialogFragment>().Count(f => f.Dialog is { IsShowing: true }) ?? -1;
#else
        return -1;
#endif
    }
}
