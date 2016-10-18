package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/bitrise-io/go-utils/cmdex"
	"github.com/bitrise-io/go-utils/fileutil"
	"github.com/bitrise-io/go-utils/log"
	"github.com/bitrise-io/go-utils/pathutil"
	"github.com/bitrise-tools/go-xamarin/builder"
	"github.com/bitrise-tools/go-xamarin/constants"
	"github.com/bitrise-tools/go-xamarin/tools/testcloud"
	shellquote "github.com/kballard/go-shellquote"
)

// ConfigsModel ...
type ConfigsModel struct {
	XamarinSolution      string
	XamarinConfiguration string
	XamarinPlatform      string

	User            string
	APIKey          string
	Devices         string
	IsAsync         string
	Series          string
	Parallelization string
	CustomOptions   string

	DeployDir string
}

func createConfigsModelFromEnvs() ConfigsModel {
	return ConfigsModel{
		XamarinSolution:      os.Getenv("xamarin_project"),
		XamarinConfiguration: os.Getenv("xamarin_configuration"),
		XamarinPlatform:      os.Getenv("xamarin_platform"),

		User:            os.Getenv("xamarin_user"),
		APIKey:          os.Getenv("test_cloud_api_key"),
		Devices:         os.Getenv("test_cloud_devices"),
		IsAsync:         os.Getenv("test_cloud_is_async"),
		Series:          os.Getenv("test_cloud_series"),
		Parallelization: os.Getenv("test_cloud_parallelization"),
		CustomOptions:   os.Getenv("other_parameters"),

		DeployDir: os.Getenv("BITRISE_DEPLOY_DIR"),
	}
}

func (configs ConfigsModel) print() {
	log.Info("Build Configs:")

	log.Detail("- XamarinSolution: %s", configs.XamarinSolution)
	log.Detail("- XamarinConfiguration: %s", configs.XamarinConfiguration)
	log.Detail("- XamarinPlatform: %s", configs.XamarinPlatform)

	log.Info("Xamarin Test Cloud Configs:")

	log.Detail("- User: %s", configs.User)
	log.Detail("- APIKey: %s", configs.APIKey)
	log.Detail("- Devices: %s", configs.Devices)
	log.Detail("- IsAsync: %s", configs.IsAsync)
	log.Detail("- Series: %s", configs.Series)
	log.Detail("- Parallelization: %s", configs.Parallelization)
	log.Detail("- CustomOptions: %s", configs.CustomOptions)

	log.Info("Other Configs:")

	log.Detail("- DeployDir: %s", configs.DeployDir)
}

func (configs ConfigsModel) validate() error {
	if configs.XamarinSolution == "" {
		return errors.New("No XamarinSolution parameter specified!")
	}
	if exist, err := pathutil.IsPathExists(configs.XamarinSolution); err != nil {
		return fmt.Errorf("Failed to check if XamarinSolution exist at: %s, error: %s", configs.XamarinSolution, err)
	} else if !exist {
		return fmt.Errorf("XamarinSolution not exist at: %s", configs.XamarinSolution)
	}

	if configs.XamarinConfiguration == "" {
		return errors.New("No XamarinConfiguration parameter specified!")
	}
	if configs.XamarinPlatform == "" {
		return errors.New("No XamarinPlatform parameter specified!")
	}

	if configs.APIKey == "" {
		return errors.New("No APIKey parameter specified!")
	}
	if configs.User == "" {
		return errors.New("No User parameter specified!")
	}
	if configs.Devices == "" {
		return errors.New("No Devices parameter specified!")
	}
	if configs.Series == "" {
		return errors.New("No Series parameter specified!")
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

func exportEnvironmentWithEnvman(keyStr, valueStr string) error {
	cmd := cmdex.NewCommand("envman", "add", "--key", keyStr)
	cmd.SetStdin(strings.NewReader(valueStr))
	return cmd.Run()
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

func main() {
	configs := createConfigsModelFromEnvs()

	fmt.Println()
	configs.print()

	if err := configs.validate(); err != nil {
		log.Error("Issue with input: %s", err)
		if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
			log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
		}
		os.Exit(1)
	}

	//
	// build
	fmt.Println()
	log.Info("Building all iOS Xamarin UITest and Referred Projects in solution: %s", configs.XamarinSolution)

	builder, err := builder.New(configs.XamarinSolution, []constants.ProjectType{constants.ProjectTypeIOS}, false)
	if err != nil {
		log.Error("Failed to create xamarin builder, error: %s", err)

		if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
			log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
		}

		os.Exit(1)
	}

	callback := func(solutionName string, projectName string, projectType constants.ProjectType, commandStr string, alreadyPerformed bool) {
		fmt.Println()
		if projectType == constants.ProjectTypeXamarinUITest {
			log.Info("Building test project: %s", projectName)
		} else {
			log.Info("Building project: %s", projectName)
		}

		log.Done("$ %s", commandStr)

		if alreadyPerformed {
			log.Warn("build command already performed, skipping...")
		}

		fmt.Println()
	}

	warnings, err := builder.BuildAllXamarinUITestAndReferredProjects(configs.XamarinConfiguration, configs.XamarinPlatform, nil, callback)
	for _, warning := range warnings {
		log.Warn(warning)
	}
	if err != nil {
		log.Error("Build failed, error: %s", err)

		if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
			log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
		}

		os.Exit(1)
	}

	projectOutputMap, err := builder.CollectProjectOutputs(configs.XamarinConfiguration, configs.XamarinPlatform)
	if err != nil {
		log.Error("Failed to collect project outputs, error: %s", err)

		if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
			log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
		}

		os.Exit(1)
	}

	testProjectOutputMap, warnings, err := builder.CollectXamarinUITestProjectOutputs(configs.XamarinConfiguration, configs.XamarinPlatform)
	for _, warning := range warnings {
		log.Warn(warning)
	}
	if err != nil {
		log.Error("Failed to collect test project output, error: %s", err)

		if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
			log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
		}

		os.Exit(1)
	}
	// ---

	//
	// Test Cloud submit
	solutionDir := filepath.Dir(configs.XamarinSolution)
	pattern := filepath.Join(solutionDir, "packages/Xamarin.UITest.*/tools/test-cloud.exe")
	testClouds, err := filepath.Glob(pattern)
	if err != nil {
		log.Error("Failed to find test-cloud.exe path with pattern (%s), error: %s", pattern, err)

		if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
			log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
		}

		os.Exit(1)
	}
	if len(testClouds) == 0 {
		if err != nil {
			log.Error("No test-cloud.exe found path with pattern (%s)", pattern)

			if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
				log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
			}

			os.Exit(1)
		}
	}

	testCloud, err := testcloud.NewModel(testClouds[0])
	if err != nil {
		log.Error("Failed to create test cloud model, error: %s", err)
		os.Exit(1)
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
			log.Error("Failed to parse parallelization, error: %s", err)

			if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
				log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
			}

			os.Exit(1)
		}

		testCloud.SetParallelization(parallelization)
	}
	// ---

	// Custom Options
	if configs.CustomOptions != "" {
		options, err := shellquote.Split(configs.CustomOptions)
		if err != nil {
			log.Error("Failed to split params (%s), error: %s", configs.CustomOptions, err)

			if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
				log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
			}

			os.Exit(1)
		}

		testCloud.SetCustomOptions(options...)
	}
	// ---

	// Artifacts
	resultLog := ""

	for testProjectName, testProjectOutput := range testProjectOutputMap {
		if len(testProjectOutput.ReferredProjectNames) == 0 {
			log.Warn("Test project (%s) does not refers to any project, skipping...", testProjectName)
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
				log.Warn("No ipa generated for project: %s", projectName)
			}
			if dsymPth == "" {
				log.Warn("No dsym generated for project: %s", projectName)
			}

			// Submit
			fmt.Println()
			log.Info("Testing (%s) against (%s)", testProjectName, projectName)
			log.Detail("test dll: %s", testProjectOutput.Output.Pth)
			log.Detail("ipa: %s", ipaPth)
			log.Detail("dsym: %s", dsymPth)

			testCloud.SetAssemblyDir(filepath.Dir(testProjectOutput.Output.Pth))
			testCloud.SetIPAPth(ipaPth)
			testCloud.SetDSYMPth(dsymPth)

			fmt.Println()
			log.Info("Submitting:")
			log.Done("$ %s", testCloud.PrintableCommand())

			lines := []string{}
			callback := func(line string) {
				log.Detail(line)

				lines = append(lines, line)
			}

			err := testCloud.Submit(callback)

			// If test cloud runs in asnyc mode test result will not be saved into file
			if configs.IsAsync != "yes" {
				testLog, logErr := testResultLogContent(resultLogPth)
				if logErr != nil {
					log.Warn("Failed to read test result, error: %s", logErr)
				}
				resultLog = testLog
			}

			if err != nil {
				log.Error("Submit failed, error: %s", err)

				if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
					log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
				}

				if resultLog != "" {
					if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", resultLog); err != nil {
						log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", err)
					}
				}

				os.Exit(1)
			}
			// ---

			if configs.IsAsync == "yes" {
				fmt.Println()
				log.Info("Preocessing json result:")

				jsonLine := ""
				for _, line := range lines {
					if strings.HasPrefix(line, "{") && strings.HasSuffix(line, "}") {
						jsonLine = line
					}
				}

				if jsonLine != "" {
					var result JSONResultModel
					if err := json.Unmarshal([]byte(jsonLine), &result); err != nil {
						log.Error("Failed to unmarshal result, error: %s", err)
					} else {
						for _, errorMsg := range result.ErrorMessages {
							log.Error(errorMsg)
						}

						if len(result.ErrorMessages) > 0 {
							if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
								log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
							}

							if resultLog != "" {
								if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", resultLog); err != nil {
									log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", err)
								}
							}

							os.Exit(1)
						}

						if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_TO_RUN_ID", result.TestRunID); err != nil {
							log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_TO_RUN_ID", err)
						}

						log.Done("TestRunId (%s) is available in (%s) environment variable", result.TestRunID, "BITRISE_XAMARIN_TEST_TO_RUN_ID")
					}
				}
			}
		}
	}
	// ---

	if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "succeeded"); err != nil {
		log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
	}

	if resultLog != "" {
		if err := exportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", resultLog); err != nil {
			log.Warn("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", err)
		}
	}
}
