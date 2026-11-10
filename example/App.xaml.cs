using Microsoft.Extensions.DependencyInjection;

namespace ModalRaceRepro;

public partial class App : Application
{
    /// <summary>Set by MainActivity from the intent extra "delay_ms" (only for the scripted run, see run.sh / run.ps1).</summary>
    public static int? AutoRunDelayMs { get; set; }

	public App()
	{
		InitializeComponent();
	}

	protected override Window CreateWindow(IActivationState? activationState)
	{
		return new Window(new AppShell());
	}
}