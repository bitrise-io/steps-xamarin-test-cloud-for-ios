package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/bitrise-io/go-utils/fileutil"
	"github.com/bitrise-io/go-utils/log"
	"github.com/bitrise-io/go-utils/pathutil"
	"github.com/bitrise-tools/go-steputils/input"
	"github.com/bitrise-tools/go-steputils/tools"
	"github.com/bitrise-tools/go-xamarin/builder"
	"github.com/bitrise-tools/go-xamarin/constants"
	"github.com/bitrise-tools/go-xamarin/tools/buildtools"
	"github.com/bitrise-tools/go-xamarin/tools/testcloud"
	shellquote "github.com/kballard/go-shellquote"
)

// ConfigsModel ...
type ConfigsModel struct {
	User    string
	APIKey  string
	Devices string
	Series  string

	XamarinSolution      string
	XamarinConfiguration string
	XamarinPlatform      string

	IsAsync         string
	Parallelization string
	CustomOptions   string
	BuildTool       string
	DeployDir       string
}

func createConfigsModelFromEnvs() ConfigsModel {
	return ConfigsModel{
		User:    os.Getenv("xamarin_user"),
		APIKey:  os.Getenv("test_cloud_api_key"),
		Devices: os.Getenv("test_cloud_devices"),
		Series:  os.Getenv("test_cloud_series"),

		XamarinSolution:      os.Getenv("xamarin_project"),
		XamarinConfiguration: os.Getenv("xamarin_configuration"),
		XamarinPlatform:      os.Getenv("xamarin_platform"),

		IsAsync:         os.Getenv("test_cloud_is_async"),
		Parallelization: os.Getenv("test_cloud_parallelization"),
		CustomOptions:   os.Getenv("other_parameters"),
		BuildTool:       os.Getenv("build_tool"),
		DeployDir:       os.Getenv("BITRISE_DEPLOY_DIR"),
	}
}

func (configs ConfigsModel) print() {
	log.Infof("Testing:")

	log.Printf("- User: %s", configs.User)
	log.Printf("- APIKey: %s", configs.APIKey)
	log.Printf("- Devices: %s", configs.Devices)
	log.Printf("- Series: %s", configs.Series)

	log.Infof("Config:")

	log.Printf("- XamarinSolution: %s", configs.XamarinSolution)
	log.Printf("- XamarinConfiguration: %s", configs.XamarinConfiguration)
	log.Printf("- XamarinPlatform: %s", configs.XamarinPlatform)

	log.Infof("Debug:")

	log.Printf("- IsAsync: %s", configs.IsAsync)
	log.Printf("- Parallelization: %s", configs.Parallelization)
	log.Printf("- CustomOptions: %s", configs.CustomOptions)
	log.Printf("- BuildTool: %s", configs.BuildTool)
	log.Printf("- DeployDir: %s", configs.DeployDir)
}

func (configs ConfigsModel) validate() error {
	if err := input.ValidateIfNotEmpty(configs.User); err != nil {
		return fmt.Errorf("User - %s", err)
	}
	if err := input.ValidateIfNotEmpty(configs.APIKey); err != nil {
		return fmt.Errorf("APIKey - %s", err)
	}
	if err := input.ValidateIfNotEmpty(configs.Devices); err != nil {
		return fmt.Errorf("Devices - %s", err)
	}
	if err := input.ValidateIfNotEmpty(configs.Series); err != nil {
		return fmt.Errorf("Series - %s", err)
	}

	if err := input.ValidateIfPathExists(configs.XamarinSolution); err != nil {
		return fmt.Errorf("XamarinSolution - %s", err)
	}
	if err := input.ValidateIfNotEmpty(configs.XamarinConfiguration); err != nil {
		return fmt.Errorf("XamarinConfiguration - %s", err)
	}
	if err := input.ValidateIfNotEmpty(configs.XamarinPlatform); err != nil {
		return fmt.Errorf("XamarinPlatform - %s", err)
	}

	if err := input.ValidateWithOptions(configs.BuildTool, "msbuild", "xbuild", "mdtool"); err != nil {
		return fmt.Errorf("BuildTool - %s", err)
	}

	return nil
}

// JSONResultModel ...
type JSONResultModel struct {
	Log           []string `json:"Log"`
	ErrorMessages []string `json:"ErrorMessages"`
	TestRunID     string   `json:"TestRunId"`
	LaunchURL     string   `json:"LaunchUrl"`
}

func testResultLogContent(pth string) (string, error) {
	if exist, err := pathutil.IsPathExists(pth); err != nil {
		return "", fmt.Errorf("Failed to check if path (%s) exist, error: %s", pth, err)
	} else if !exist {
		return "", fmt.Errorf("test result not exist at: %s", pth)
	}

	content, err := fileutil.ReadStringFromFile(pth)
	if err != nil {
		return "", fmt.Errorf("Failed to read file (%s), error: %s", pth, err)
	}

	return content, nil
}

func failf(format string, v ...interface{}) {
	log.Errorf(format, v...)
	if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
		log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
	}
	os.Exit(1)
}

func main() {
	configs := createConfigsModelFromEnvs()

	fmt.Println()
	configs.print()

	if err := configs.validate(); err != nil {
		failf("Issue with input: %s", err)
	}

	//
	// build
	fmt.Println()
	log.Infof("Building all iOS Xamarin UITest and Referred Projects in solution: %s", configs.XamarinSolution)

	buildTool := buildtools.Xbuild
	if configs.BuildTool == "mdtool" {
		buildTool = buildtools.Mdtool
	} else if configs.BuildTool == "msbuild" {
		buildTool = buildtools.Msbuild
	}

	builder, err := builder.New(configs.XamarinSolution, []constants.SDK{constants.SDKIOS}, buildTool)
	if err != nil {
		failf("Failed to create xamarin builder, error: %s", err)
	}

	callback := func(solutionName string, projectName string, sdk constants.SDK, testFramework constants.TestFramework, commandStr string, alreadyPerformed bool) {
		fmt.Println()
		if projectName == "" {
			log.Infof("Building solution: %s", solutionName)
		} else {
			if testFramework == constants.TestFrameworkXamarinUITest {
				log.Infof("Building test project: %s", projectName)
			} else {
				log.Infof("Building project: %s", projectName)
			}
		}

		log.Donef("$ %s", commandStr)

		if alreadyPerformed {
			log.Warnf("build command already performed, skipping...")
		}

		fmt.Println()
	}

	startTime := time.Now()
	warnings, err := builder.BuildAllUITestableXamarinProjects(configs.XamarinConfiguration, configs.XamarinPlatform, nil, callback)
	endTime := time.Now()

	for _, warning := range warnings {
		log.Warnf(warning)
	}
	if err != nil {
		failf("Build failed, error: %s", err)
	}

	projectOutputMap, err := builder.CollectProjectOutputs(configs.XamarinConfiguration, configs.XamarinPlatform, startTime, endTime)
	if err != nil {
		failf("Failed to collect project outputs, error: %s", err)
	}

	testProjectOutputMap, warnings, err := builder.CollectXamarinUITestProjectOutputs(configs.XamarinConfiguration, configs.XamarinPlatform, startTime, endTime)
	for _, warning := range warnings {
		log.Warnf(warning)
	}
	if err != nil {
		failf("Failed to collect test project output, error: %s", err)
	}
	if len(testProjectOutputMap) == 0 {
		failf("No testable output generated")
	}
	// ---

	//
	// Test Cloud submit
	solutionDir := filepath.Dir(configs.XamarinSolution)
	pattern := filepath.Join(solutionDir, "packages/Xamarin.UITest.*/tools/test-cloud.exe")
	testClouds, err := filepath.Glob(pattern)
	if err != nil {
		failf("Failed to find test-cloud.exe path with pattern (%s), error: %s", pattern, err)
	}
	if len(testClouds) == 0 {
		if err != nil {
			failf("No test-cloud.exe found path with pattern (%s)", pattern)
		}
	}

	testCloud, err := testcloud.NewModel(testClouds[0])
	if err != nil {
		failf("Failed to create test cloud model, error: %s", err)
	}

	testCloud.SetAPIKey(configs.APIKey)
	testCloud.SetUser(configs.User)
	testCloud.SetDevices(configs.Devices)
	testCloud.SetIsAsyncJSON(configs.IsAsync == "yes")
	testCloud.SetSeries(configs.Series)

	// If test cloud runs in asnyc mode test result will not be saved into file
	resultLogPth := filepath.Join(configs.DeployDir, "TestResult.xml")
	if configs.IsAsync != "yes" {
		testCloud.SetNunitXMLPth(resultLogPth)
	}

	// Parallelization
	if configs.Parallelization != "none" {
		parallelization, err := testcloud.ParseParallelization(configs.Parallelization)
		if err != nil {
			failf("Failed to parse parallelization, error: %s", err)
		}

		testCloud.SetParallelization(parallelization)
	}
	// ---

	// Custom Options
	if configs.CustomOptions != "" {
		options, err := shellquote.Split(configs.CustomOptions)
		if err != nil {
			failf("Failed to split params (%s), error: %s", configs.CustomOptions, err)
		}

		testCloud.SetCustomOptions(options...)
	}
	// ---

	// Artifacts
	resultLog := ""

	for testProjectName, testProjectOutput := range testProjectOutputMap {
		if len(testProjectOutput.ReferredProjectNames) == 0 {
			log.Warnf("Test project (%s) does not refers to any project, skipping...", testProjectName)
			continue
		}

		for _, projectName := range testProjectOutput.ReferredProjectNames {
			projectOutput, ok := projectOutputMap[projectName]
			if !ok {
				continue
			}

			ipaPth := ""
			dsymPth := ""
			for _, output := range projectOutput.Outputs {
				if output.OutputType == constants.OutputTypeIPA {
					ipaPth = output.Pth
				}

				if output.OutputType == constants.OutputTypeDSYM {
					dsymPth = output.Pth
				}
			}

			if ipaPth == "" {
				log.Warnf("No ipa generated for project: %s", projectName)
			}
			if dsymPth == "" {
				log.Warnf("No dsym generated for project: %s", projectName)
			}

			// Submit
			fmt.Println()
			log.Infof("Testing (%s) against (%s)", testProjectName, projectName)
			log.Printf("test dll: %s", testProjectOutput.Output.Pth)
			log.Printf("ipa: %s", ipaPth)
			log.Printf("dsym: %s", dsymPth)

			testCloud.SetAssemblyDir(filepath.Dir(testProjectOutput.Output.Pth))
			testCloud.SetIPAPth(ipaPth)
			testCloud.SetDSYMPth(dsymPth)

			fmt.Println()
			log.Infof("Submitting:")
			log.Donef("$ %s", testCloud.PrintableCommand())

			lines := []string{}
			callback := func(line string) {
				log.Printf(line)

				lines = append(lines, line)
			}

			err := testCloud.Submit(callback)

			// If test cloud runs in asnyc mode test result will not be saved into file
			if configs.IsAsync != "yes" {
				testLog, logErr := testResultLogContent(resultLogPth)
				if logErr != nil {
					log.Warnf("Failed to read test result, error: %s", logErr)
				}
				resultLog = testLog
			}

			if err != nil {
				log.Errorf("Submit failed, error: %s", err)

				if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
					log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
				}

				if resultLog != "" {
					if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", resultLog); err != nil {
						log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", err)
					}
				}

				os.Exit(1)
			}
			// ---

			if configs.IsAsync == "yes" {
				fmt.Println()
				log.Infof("Preocessing json result:")

				jsonLine := ""
				for _, line := range lines {
					if strings.HasPrefix(line, "{") && strings.HasSuffix(line, "}") {
						jsonLine = line
					}
				}

				if jsonLine != "" {
					var result JSONResultModel
					if err := json.Unmarshal([]byte(jsonLine), &result); err != nil {
						log.Errorf("Failed to unmarshal result, error: %s", err)
					} else {
						for _, errorMsg := range result.ErrorMessages {
							log.Errorf(errorMsg)
						}

						if len(result.ErrorMessages) > 0 {
							if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
								log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
							}

							if resultLog != "" {
								if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", resultLog); err != nil {
									log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", err)
								}
							}

							os.Exit(1)
						}

						if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_TO_RUN_ID", result.TestRunID); err != nil {
							log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_TO_RUN_ID", err)
						}

						log.Donef("TestRunId (%s) is available in (%s) environment variable", result.TestRunID, "BITRISE_XAMARIN_TEST_TO_RUN_ID")
					}
				}
			}
		}
	}
	// ---

	if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "succeeded"); err != nil {
		log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
	}

	if resultLog != "" {
		if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", resultLog); err != nil {
			log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", err)
		}
	}
}
